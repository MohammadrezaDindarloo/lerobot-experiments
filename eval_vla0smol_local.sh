#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" == "Darwin" ]]; then
  export PYTORCH_ENABLE_MPS_FALLBACK=1
fi

# Force CPU for laptop stability (remove if you want MPS/CUDA)
export ACCELERATE_USE_CPU=1
export ACCELERATE_MIXED_PRECISION=no

POLICY_PATH="${POLICY_PATH:-outputs/train/latest/checkpoints/last/pretrained_model}"
ENV_TYPE="${ENV_TYPE:-libero}"
ENV_TASK="${ENV_TASK:-libero_object}"

PYTHONPATH="$(pwd)/src${PYTHONPATH:+:$PYTHONPATH}" \
python -m lerobot.scripts.lerobot_eval \
  --policy.path="${POLICY_PATH}" \
  --env.type="${ENV_TYPE}" \
  --env.task="${ENV_TASK}" \
  --eval.batch_size=1
