#!/usr/bin/env bash
set -euo pipefail

REPO_ID="${REPO_ID:-HuggingFaceVLA/libero}"

DATASET_ROOT="${DATASET_ROOT:-/home/s2816905/datasets/HuggingFaceVLA_libero}"
mkdir -p "$DATASET_ROOT"

echo "Downloading dataset:"
echo "  REPO_ID=$REPO_ID"
echo "  DATASET_ROOT=$DATASET_ROOT"

# Prefer huggingface-cli when available.
if command -v huggingface-cli >/dev/null 2>&1; then
  huggingface-cli download \
    --repo-type dataset \
    "$REPO_ID" \
    --local-dir "$DATASET_ROOT"
else
  python - <<'PY'
from huggingface_hub import snapshot_download
import os

repo_id = os.environ.get("REPO_ID", "HuggingFaceVLA/libero")
dataset_root = os.environ["DATASET_ROOT"]
snapshot_download(repo_id=repo_id, repo_type="dataset", local_dir=dataset_root)
print(f"Downloaded {repo_id} to {dataset_root}")
PY
fi

echo "Done."
