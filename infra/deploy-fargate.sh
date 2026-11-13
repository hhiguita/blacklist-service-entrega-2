#!/usr/bin/env bash
# Paso 3. Crea o actualiza ALB + cluster + servicio Fargate + CodeDeploy (fargate-stack.yaml).
# Requiere base-stack.yaml desplegado y la imagen inicial (bootstrap-image.sh).
# Uso: ./deploy-fargate.sh <perfil-aws>
set -euo pipefail

PROFILE="${1:-default}"
REGION="us-east-1"
STACK="blacklist-fargate"
DIR="$(cd "$(dirname "$0")" && pwd)"
AWSX=(--region "$REGION" --profile "$PROFILE")

out() {
  aws cloudformation describe-stacks --stack-name blacklist-base "${AWSX[@]}" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

VPC=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true "${AWSX[@]}" \
  --query "Vpcs[0].VpcId" --output text)
SUBNETS=$(aws ec2 describe-subnets "${AWSX[@]}" \
  --filters Name=vpc-id,Values="$VPC" Name=default-for-az,Values=true \
  --query "sort_by(Subnets[?AvailabilityZone!='us-east-1e'],&AvailabilityZone)[0:2].SubnetId" \
  --output text | tr '\t' ',')

aws cloudformation deploy \
  --template-file "${DIR}/fargate-stack.yaml" \
  --stack-name "$STACK" \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    "VpcId=${VPC}" "SubnetIds=${SUBNETS}" \
    "DBHost=$(out DBHost)" \
    "DBSecretArn=$(out DBSecretArn)" \
    "DBSecurityGroupId=$(out DBSecurityGroupId)" \
    "TokenSecretArn=$(out TokenSecretArn)" \
    "JwtSecretArn=$(out JwtSecretArn)" \
  "${AWSX[@]}"

aws cloudformation describe-stacks --stack-name "$STACK" "${AWSX[@]}" \
  --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" --output table
