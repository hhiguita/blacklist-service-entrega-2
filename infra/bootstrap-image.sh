#!/usr/bin/env bash
# Paso 2. Despliegue MANUAL inicial: construye la imagen localmente y la sube a ECR con
# el tag "bootstrap". El servicio Fargate necesita una imagen existente para arrancar.
# Requiere Docker en marcha (Colima: `colima start`). Desde aqui, los despliegues los
# hace el pipeline con una imagen por commit.
# Uso: ./bootstrap-image.sh <perfil-aws>
set -euo pipefail

PROFILE="${1:-default}"
REGION="us-east-1"
TAG="bootstrap"
DIR="$(cd "$(dirname "$0")" && pwd)"
AWSX=(--region "$REGION" --profile "$PROFILE")

URI=$(aws cloudformation describe-stacks --stack-name blacklist-base "${AWSX[@]}" \
  --query "Stacks[0].Outputs[?OutputKey=='RepositoryUri'].OutputValue" --output text)
REGISTRY="${URI%%/*}"

aws ecr get-login-password "${AWSX[@]}" | docker login --username AWS --password-stdin "$REGISTRY"
# Fargate corre en x86_64: en un Mac con Apple Silicon hay que forzar la plataforma.
docker build --platform linux/amd64 -t "${URI}:${TAG}" "${DIR}/.."
docker push "${URI}:${TAG}"
echo "Imagen inicial publicada: ${URI}:${TAG}"
