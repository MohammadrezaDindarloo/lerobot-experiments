#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" == "Darwin" ]]; then
  export PYTORCH_ENABLE_MPS_FALLBACK=1
fi

# Run evaluation
lerobot-eval \
  --policy.path="Robot-Learning-Collective/VLA-0-Smol" \
  --policy.n_action_steps=0 \
  --policy.ensemble_size=8 \
  --env.type=libero \
  --env.task=libero_object \
  --eval.batch_size=1
