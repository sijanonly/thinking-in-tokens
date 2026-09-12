#!/usr/bin/env bash

set -euo pipefail

CONTAINER_NAME="thinking-in-tokens-preview"
IMAGE_NAME="${IMAGE_NAME:-thinking-in-tokens:local}"

docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true

docker create \
  --name "${CONTAINER_NAME}" \
  "${IMAGE_NAME}"

rm -rf .docker-preview
mkdir -p .docker-preview

docker cp \
  "${CONTAINER_NAME}:/repo/output/." \
  .docker-preview/

docker rm "${CONTAINER_NAME}"

echo "Serving the generated website at http://localhost:8000"

cd .docker-preview
python3 -m http.server 8001
