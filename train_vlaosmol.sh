#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" == "Darwin" ]]; then
  export PYTORCH_ENABLE_MPS_FALLBACK=1
fi

lerobot-train \
  --config_path configs/vla0_smol_libero_custom.json 