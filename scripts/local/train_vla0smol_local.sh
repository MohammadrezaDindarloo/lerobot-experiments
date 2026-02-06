#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" == "Darwin" ]]; then
  export PYTORCH_ENABLE_MPS_FALLBACK=1
fi

# Force CPU for laptop stability (remove if you want MPS/CUDA)
export ACCELERATE_USE_CPU=1
export ACCELERATE_MIXED_PRECISION=no

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

CONFIG_PATH="${CONFIG_PATH:-${REPO_ROOT}/configs/vla0_smol_cons_libero_laptop.json}"

PYTHONPATH="${REPO_ROOT}/src${PYTHONPATH:+:$PYTHONPATH}" \
python -m lerobot.scripts.lerobot_train \
  --config_path "${CONFIG_PATH}"
