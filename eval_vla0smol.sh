#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" == "Darwin" ]]; then
  export PYTORCH_ENABLE_MPS_FALLBACK=1
fi

# Run evaluation
# --policy.path="Robot-Learning-Collective/VLA-0-Smol" \
lerobot-eval \
  --policy.path="MohammadrezaD/vla0_smol_pusht" \
  --policy.n_action_steps=0 \
  --policy.ensemble_size=8 \
  --env.type=libero \
  --env.task=libero_object \
  --eval.batch_size=1
