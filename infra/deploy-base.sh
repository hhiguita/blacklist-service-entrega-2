#!/usr/bin/env bash
# Paso 1. Crea o actualiza ECR + RDS + secretos (base-stack.yaml).
# Uso:
#   export STATIC_BEARER_TOKEN='...'   # min 16 caracteres, sin comillas dobles ni \
#   export JWT_SECRET_KEY='...'        # min 16 caracteres
#   ./deploy-base.sh <perfil-aws>
set -euo pipefail

PROFILE="${1:-default}"
REGION="us-east-1"
STACK="blacklist-base"
DIR="$(cd "$(dirname "$0")" && pwd)"
AWSX=(--region "$REGION" --profile "$PROFILE")

: "${STATIC_BEARER_TOKEN:?Define STATIC_BEARER_TOKEN (min 16 caracteres)}"
: "${JWT_SECRET_KEY:?Define JWT_SECRET_KEY (min 16 caracteres)}"

VPC=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true "${AWSX[@]}" \
  --query "Vpcs[0].VpcId" --output text)
# 2 subredes por defecto en AZ distintas, evitando us-east-1e (no soporta t3).
SUBNETS=$(aws ec2 describe-subnets "${AWSX[@]}" \
  --filters Name=vpc-id,Values="$VPC" Name=default-for-az,Values=true \
  --query "sort_by(Subnets[?AvailabilityZone!='us-east-1e'],&AvailabilityZone)[0:2].SubnetId" \
  --output text | tr '\t' ',')
echo "VPC: ${VPC}  Subnets: ${SUBNETS}"

aws cloudformation deploy \
  --template-file "${DIR}/base-stack.yaml" \
  --stack-name "$STACK" \
  --parameter-overrides \
    "VpcId=${VPC}" "SubnetIds=${SUBNETS}" \
    "StaticBearerToken=${STATIC_BEARER_TOKEN}" "JwtSecretKey=${JWT_SECRET_KEY}" \
  "${AWSX[@]}"

aws cloudformation describe-stacks --stack-name "$STACK" "${AWSX[@]}" \
  --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" --output table
