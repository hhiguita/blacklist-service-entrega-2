#!/usr/bin/env bash
# Paso 4. Crea o actualiza el pipeline CI/CD (ci-pipeline.yaml).
# Requiere base-stack.yaml y fargate-stack.yaml desplegados: sus outputs se pasan como parametros.
# Uso: ./deploy-ci.sh [perfil-aws] [arn-conexion-existente]
#   ./deploy-ci.sh uniandes          -> si el stack ya existe, conserva su conexion GitHub
#   ./deploy-ci.sh uniandes arn:...  -> usa una conexion ya autorizada (solo en un stack nuevo)
set -euo pipefail

PROFILE="${1:-default}"
CONNECTION_ARN="${2:-}"
STACK="blacklist-ci"
REGION="us-east-1"
DIR="$(cd "$(dirname "$0")" && pwd)"
AWSX=(--region "$REGION" --profile "$PROFILE")

out() {  # out <stack> <OutputKey>
  aws cloudformation describe-stacks --stack-name "$1" "${AWSX[@]}" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text
}

aws cloudformation validate-template \
  --template-body "file://${DIR}/ci-pipeline.yaml" "${AWSX[@]}" >/dev/null
echo "Plantilla valida."

aws cloudformation deploy \
  --template-file "${DIR}/ci-pipeline.yaml" \
  --stack-name "$STACK" \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    "ExistingConnectionArn=${CONNECTION_ARN}" \
    "EcrRepositoryName=$(out blacklist-base RepositoryName)" \
    "DBHost=$(out blacklist-base DBHost)" \
    "DBSecretArn=$(out blacklist-base DBSecretArn)" \
    "TokenSecretArn=$(out blacklist-base TokenSecretArn)" \
    "JwtSecretArn=$(out blacklist-base JwtSecretArn)" \
    "TaskExecutionRoleArn=$(out blacklist-fargate TaskExecutionRoleArn)" \
    "TaskRoleArn=$(out blacklist-fargate TaskRoleArn)" \
    "CodeDeployApplicationName=$(out blacklist-fargate CodeDeployApplicationName)" \
    "DeploymentGroupName=$(out blacklist-fargate DeploymentGroupName)" \
  "${AWSX[@]}"

aws cloudformation describe-stacks --stack-name "$STACK" "${AWSX[@]}" \
  --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" --output table

echo ""
echo "Si la conexion GitHub esta PENDING: Developer Tools > Settings > Connections >"
echo "'Update pending connection'. Despues: CodePipeline > Release change."
