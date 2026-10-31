#!/usr/bin/env bash
# Crea o actualiza Beanstalk + RDS desplegando el artefacto de un commit concreto.
# Requisito: el stack de CI existe y el pipeline ya genero builds/app-<commit>.zip.
#
# Uso:
#   export STATIC_BEARER_TOKEN='...'   # min 16 caracteres
#   export JWT_SECRET_KEY='...'        # min 16 caracteres
#   ./deploy-app.sh <perfil-aws> [commit-sha]   # sin sha: usa el artefacto mas reciente
set -euo pipefail

PROFILE="${1:-default}"
SHA="${2:-}"
REGION="us-east-1"
CI_STACK="blacklist-ci"
APP_STACK="blacklist-app"
DIR="$(cd "$(dirname "$0")" && pwd)"
AWSX=(--region "$REGION" --profile "$PROFILE")

: "${STATIC_BEARER_TOKEN:?Define STATIC_BEARER_TOKEN (min 16 caracteres)}"
: "${JWT_SECRET_KEY:?Define JWT_SECRET_KEY (min 16 caracteres)}"

BUCKET=$(aws cloudformation describe-stacks --stack-name "$CI_STACK" "${AWSX[@]}" \
  --query "Stacks[0].Outputs[?OutputKey=='ArtifactBucketName'].OutputValue" --output text)

if [ -n "$SHA" ]; then
  KEY=$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "builds/app-${SHA}" "${AWSX[@]}" \
    --query "Contents[0].Key" --output text)
else
  KEY=$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "builds/" "${AWSX[@]}" \
    --query "sort_by(Contents,&LastModified)[-1].Key" --output text)
fi
[ "$KEY" != "None" ] && [ -n "$KEY" ] || { echo "No hay artefacto en s3://${BUCKET}/builds/ (corre el pipeline primero)"; exit 1; }
echo "Artefacto a desplegar: s3://${BUCKET}/${KEY}"

STACK_NAME=$(aws elasticbeanstalk list-available-solution-stacks "${AWSX[@]}" \
  --query "SolutionStacks[?contains(@, 'Amazon Linux 2023') && contains(@, 'running Python 3.12')] | [0]" \
  --output text)
[ "$STACK_NAME" != "None" ] || { echo "No encontre plataforma Python 3.12 en AL2023"; exit 1; }
echo "Plataforma: ${STACK_NAME}"

VPC=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true "${AWSX[@]}" \
  --query "Vpcs[0].VpcId" --output text)
# 2 subredes por defecto en AZ distintas, evitando us-east-1e (no soporta t3).
SUBNETS=$(aws ec2 describe-subnets "${AWSX[@]}" \
  --filters Name=vpc-id,Values="$VPC" Name=default-for-az,Values=true \
  --query "sort_by(Subnets[?AvailabilityZone!='us-east-1e'],&AvailabilityZone)[0:2].SubnetId" \
  --output text | tr '\t' ',')
echo "VPC: ${VPC}  Subnets: ${SUBNETS}"

aws cloudformation deploy \
  --template-file "${DIR}/eb-app.yaml" \
  --stack-name "$APP_STACK" \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    "SolutionStackName=${STACK_NAME}" \
    "VpcId=${VPC}" \
    "SubnetIds=${SUBNETS}" \
    "SourceBundleBucket=${BUCKET}" \
    "SourceBundleKey=${KEY}" \
    "StaticBearerToken=${STATIC_BEARER_TOKEN}" \
    "JwtSecretKey=${JWT_SECRET_KEY}" \
  "${AWSX[@]}"

aws cloudformation describe-stacks --stack-name "$APP_STACK" "${AWSX[@]}" \
  --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" --output table
