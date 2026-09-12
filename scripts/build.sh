#!/usr/bin/env bash

set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-thinking-in-tokens:local}"

echo "Building Docker image: ${IMAGE_NAME}"

docker build \
  --tag "${IMAGE_NAME}" \
  .

echo "Docker build completed successfully."
