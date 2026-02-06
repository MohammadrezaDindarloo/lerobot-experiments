#!/usr/bin/env bash
set -euo pipefail

POLICY_PATH="${POLICY_PATH:-outputs/train/latest/checkpoints/last/pretrained_model}"
ENV_TYPE="${ENV_TYPE:-libero}"
ENV_TASK="${ENV_TASK:-libero_object}"

PYTHONPATH="$(pwd)/src${PYTHONPATH:+:$PYTHONPATH}" \
python -m lerobot.scripts.lerobot_eval \
  --policy.path="${POLICY_PATH}" \
  --env.type="${ENV_TYPE}" \
  --env.task="${ENV_TASK}" \
  --eval.batch_size=1
