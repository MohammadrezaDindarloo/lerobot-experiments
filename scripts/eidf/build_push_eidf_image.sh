#!/usr/bin/env bash
set -euo pipefail

# Build and push a Linux container image containing a conda environment.
# Intended for EIDF cluster use.

IMAGE_REPO="${IMAGE_REPO:-ghcr.io/REPLACE_ME/lerobot-vla0smol}"
IMAGE_TAG="${IMAGE_TAG:-$(date +%Y%m%d-%H%M%S)}"
IMAGE="${IMAGE_REPO}:${IMAGE_TAG}"
PLATFORM="${PLATFORM:-linux/amd64}"
CONDA_ENV_NAME="${CONDA_ENV_NAME:-vla0smol}"
CONDA_ENV_FILE="${CONDA_ENV_FILE:-docker/conda/vla0smol.linux.yml}"
PIP_INSTALL_CMD="${PIP_INSTALL_CMD:-python -m pip install --no-cache-dir -e .[libero,vla0_smol]}"

if [[ ! -f "$CONDA_ENV_FILE" ]]; then
  echo "[ERROR] Missing conda env file: $CONDA_ENV_FILE" >&2
  echo "        Run: ENV_NAME=vla0smol scripts/eidf/export_conda_spec.sh" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "[ERROR] docker not found in PATH." >&2
  exit 1
fi

echo "[INFO] Building and pushing image: $IMAGE"
echo "[INFO] Platform: $PLATFORM"
echo "[INFO] Conda env: $CONDA_ENV_NAME"
echo "[INFO] Conda spec: $CONDA_ENV_FILE"
echo "[INFO] Pip install: $PIP_INSTALL_CMD"

docker buildx build \
  --platform "$PLATFORM" \
  -f docker/conda/Dockerfile.eidf-conda \
  --build-arg CONDA_ENV_FILE="$CONDA_ENV_FILE" \
  --build-arg CONDA_ENV_NAME="$CONDA_ENV_NAME" \
  --build-arg PIP_INSTALL_CMD="$PIP_INSTALL_CMD" \
  -t "$IMAGE" \
  --push \
  .

echo "[INFO] Done."
echo "[INFO] Use this image for EIDF jobs: IMAGE=$IMAGE"
