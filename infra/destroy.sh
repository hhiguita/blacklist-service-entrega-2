#!/usr/bin/env bash
# Borra todo: primero la app (Beanstalk + RDS), luego el CI (vacia el bucket antes).
# Uso: ./destroy.sh [perfil-aws] [app|ci|all]   (por defecto: all)
set -euo pipefail

PROFILE="${1:-default}"
WHAT="${2:-all}"
REGION="us-east-1"
CI_STACK="blacklist-ci"
APP_STACK="blacklist-app"
AWSX=(--region "$REGION" --profile "$PROFILE")

exists() { aws cloudformation describe-stacks --stack-name "$1" "${AWSX[@]}" >/dev/null 2>&1; }

read -r -p "Se borrara: ${WHAT}. Escribe 'borrar' para confirmar: " OK
[ "$OK" = "borrar" ] || { echo "Cancelado."; exit 1; }

if [[ "$WHAT" == "all" || "$WHAT" == "app" ]] && exists "$APP_STACK"; then
  echo "Borrando ${APP_STACK} (Beanstalk + RDS, tarda varios minutos)..."
  aws cloudformation delete-stack --stack-name "$APP_STACK" "${AWSX[@]}"
  aws cloudformation wait stack-delete-complete --stack-name "$APP_STACK" "${AWSX[@]}"
  echo "${APP_STACK} eliminado."
fi

if [[ "$WHAT" == "all" || "$WHAT" == "ci" ]] && exists "$CI_STACK"; then
  BUCKET=$(aws cloudformation describe-stacks --stack-name "$CI_STACK" "${AWSX[@]}" \
    --query "Stacks[0].Outputs[?OutputKey=='ArtifactBucketName'].OutputValue" --output text)
  echo "Vaciando s3://${BUCKET} ..."
  aws s3 rm "s3://${BUCKET}" --recursive "${AWSX[@]}"
  aws cloudformation delete-stack --stack-name "$CI_STACK" "${AWSX[@]}"
  aws cloudformation wait stack-delete-complete --stack-name "$CI_STACK" "${AWSX[@]}"
  echo "${CI_STACK} eliminado."
fi

echo "Nota: Beanstalk crea su propio bucket elasticbeanstalk-${REGION}-<cuenta> que no pertenece a ningun stack."
