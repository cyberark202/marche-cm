#!/usr/bin/env bash
# Build de l'image backend + push vers ECR. Tag = sha court du commit.
# Usage: ECR_URL=<repo> AWS_REGION=eu-north-1 ./build-and-push.sh
set -euo pipefail

ECR_URL="${ECR_URL:?Renseigner ECR_URL (sortie terraform: ecr_repository_url)}"
AWS_REGION="${AWS_REGION:-eu-north-1}"
TAG="${TAG:-$(git rev-parse --short HEAD)}"
REGISTRY="${ECR_URL%/*}"

cd "$(dirname "$0")/../backend"

echo ">> Login ECR ($REGISTRY)"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY"

echo ">> Build $ECR_URL:$TAG"
docker build -t "$ECR_URL:$TAG" -t "$ECR_URL:latest" .

echo ">> Push"
docker push "$ECR_URL:$TAG"
docker push "$ECR_URL:latest"

echo ">> OK. Déployer: helm upgrade --install marche-cm ../k8s/marche-cm -n marche-cm -f ../k8s/marche-cm/values-prod.yaml --set image.tag=$TAG"
