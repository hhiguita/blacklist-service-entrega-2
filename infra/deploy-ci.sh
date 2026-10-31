#!/usr/bin/env bash
# Crea o actualiza el stack de CI.
# Uso: ./deploy.sh [perfil-aws] [arn-conexion-existente]
#   ./deploy.sh                      -> perfil default, crea conexion nueva (PENDING)
#   ./deploy.sh mi-perfil arn:aws:codeconnections:us-east-1:123:connection/abc
set -euo pipefail

PROFILE="${1:-default}"
CONNECTION_ARN="${2:-}"
STACK="blacklist-ci"
REGION="us-east-1"
DIR="$(cd "$(dirname "$0")" && pwd)"

aws cloudformation validate-template \
  --template-body "file://${DIR}/ci-pipeline.yaml" \
  --region "$REGION" --profile "$PROFILE" >/dev/null
echo "Plantilla valida."

aws cloudformation deploy \
  --template-file "${DIR}/ci-pipeline.yaml" \
  --stack-name "$STACK" \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides "ExistingConnectionArn=${CONNECTION_ARN}" \
  --region "$REGION" --profile "$PROFILE"

aws cloudformation describe-stacks --stack-name "$STACK" \
  --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" --output table \
  --region "$REGION" --profile "$PROFILE"

if [ -z "$CONNECTION_ARN" ]; then
  echo ""
  echo "SIGUIENTE PASO MANUAL: Developer Tools > Settings > Connections >"
  echo "selecciona la conexion PENDING > 'Update pending connection' > autoriza la GitHub App."
  echo "Despues: CodePipeline > ${STACK} pipeline > 'Release change'."
fi
