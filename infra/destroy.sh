#!/usr/bin/env bash
# Borra todo en orden inverso: pipeline (CI/CD), Fargate y base (ECR + RDS).
# Uso: ./destroy.sh [perfil-aws] [ci|fargate|base|all]   (por defecto: all)
set -euo pipefail

PROFILE="${1:-default}"
WHAT="${2:-all}"
REGION="us-east-1"
AWSX=(--region "$REGION" --profile "$PROFILE")

exists() { aws cloudformation describe-stacks --stack-name "$1" "${AWSX[@]}" >/dev/null 2>&1; }
drop() {
  echo "Borrando $1 ..."
  aws cloudformation delete-stack --stack-name "$1" "${AWSX[@]}"
  aws cloudformation wait stack-delete-complete --stack-name "$1" "${AWSX[@]}"
  echo "$1 eliminado."
}

read -r -p "Se borrara: ${WHAT}. Escribe 'borrar' para confirmar: " OK
[ "$OK" = "borrar" ] || { echo "Cancelado."; exit 1; }

if [[ "$WHAT" == "all" || "$WHAT" == "ci" ]] && exists blacklist-ci; then
  BUCKET=$(aws cloudformation describe-stacks --stack-name blacklist-ci "${AWSX[@]}" \
    --query "Stacks[0].Outputs[?OutputKey=='ArtifactBucketName'].OutputValue" --output text)
  echo "Vaciando s3://${BUCKET} ..."
  aws s3 rm "s3://${BUCKET}" --recursive "${AWSX[@]}"
  drop blacklist-ci
fi
if [[ "$WHAT" == "all" || "$WHAT" == "fargate" ]] && exists blacklist-fargate; then drop blacklist-fargate; fi
# El repositorio ECR tiene EmptyOnDelete: se vacia solo al borrar el stack.
if [[ "$WHAT" == "all" || "$WHAT" == "base" ]] && exists blacklist-base; then drop blacklist-base; fi
