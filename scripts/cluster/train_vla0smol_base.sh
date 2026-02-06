#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

CONFIG_PATH="${CONFIG_PATH:-${REPO_ROOT}/configs/vla0_smol_libero_custom.json}"
if [[ "${CONFIG_PATH}" != /* ]]; then
  CONFIG_PATH="${REPO_ROOT}/${CONFIG_PATH}"
fi

PYTHONPATH="${REPO_ROOT}/src${PYTHONPATH:+:$PYTHONPATH}" \
python -m lerobot.scripts.lerobot_train \
  --config_path "${CONFIG_PATH}"
