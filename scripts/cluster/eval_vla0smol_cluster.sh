#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Default to latest local checkpoint if POLICY_PATH not provided
if [[ -z "${POLICY_PATH:-}" ]]; then
  POLICY_PATH=$(ls -td "${REPO_ROOT}"/outputs/train/*/*/checkpoints/last/pretrained_model 2>/dev/null | head -n 1 || true)
fi

# If POLICY_PATH is a relative local path, resolve it from repo root.
if [[ -n "${POLICY_PATH:-}" && "${POLICY_PATH}" != /* && -d "${REPO_ROOT}/${POLICY_PATH}" ]]; then
  POLICY_PATH="${REPO_ROOT}/${POLICY_PATH}"
fi

if [[ -z "${POLICY_PATH:-}" ]]; then
  echo "No local policy checkpoint found. Set POLICY_PATH to a local checkpoint or HF repo id." >&2
  exit 1
fi

ENV_TYPE="${ENV_TYPE:-libero}"
ENV_TASK="${ENV_TASK:-libero_object}"

PYTHONPATH="${REPO_ROOT}/src${PYTHONPATH:+:$PYTHONPATH}" \
python -m lerobot.scripts.lerobot_eval \
  --policy.path="${POLICY_PATH}" \
  --env.type="${ENV_TYPE}" \
  --env.task="${ENV_TASK}" \
  --eval.batch_size=1
