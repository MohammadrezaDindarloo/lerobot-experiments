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

# POLICY_PATH can be a local checkpoint directory or a Hugging Face repo id
# Override by setting POLICY_PATH in the environment.
POLICY_PATH="${POLICY_PATH:-MohammadrezaD/vla0_smol_pusht}"

# Default to latest local checkpoint if POLICY_PATH not provided
if [[ -z "${POLICY_PATH:-}" ]]; then
  POLICY_PATH=$(ls -td "${REPO_ROOT}"/outputs/train/*/*/checkpoints/last/pretrained_model 2>/dev/null | head -n 1 || true)
fi

# Validate only if POLICY_PATH is a local directory.
if [[ -z "${POLICY_PATH:-}" ]]; then
  echo "No local policy checkpoint found. Set POLICY_PATH to a local checkpoint or HF repo id." >&2
  exit 1
fi
if [[ "${POLICY_PATH}" == /* || "${POLICY_PATH}" == ./* || "${POLICY_PATH}" == ../* ]]; then
  if [[ ! -d "${POLICY_PATH}" ]]; then
    echo "Local policy path not found: ${POLICY_PATH}" >&2
    exit 1
  fi
fi

ENV_TYPE="${ENV_TYPE:-libero}"
ENV_TASK="${ENV_TASK:-libero_object}"

PYTHONPATH="${REPO_ROOT}/src${PYTHONPATH:+:$PYTHONPATH}" \
python -m lerobot.scripts.lerobot_eval \
  --policy.path="${POLICY_PATH}" \
  --env.type="${ENV_TYPE}" \
  --env.task="${ENV_TASK}" \
  --eval.batch_size=1
