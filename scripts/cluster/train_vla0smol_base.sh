#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

CONFIG_PATH="${CONFIG_PATH:-${REPO_ROOT}/configs/vla0_smol_libero_custom.json}"
if [[ "${CONFIG_PATH}" != /* ]]; then
  CONFIG_PATH="${REPO_ROOT}/${CONFIG_PATH}"
fi

NUM_GPUS="${NUM_GPUS:-1}"
MASTER_PORT="${MASTER_PORT:-29500}"
DATASET_ROOT="${DATASET_ROOT:-}"
FORCE_RESUME="${FORCE_RESUME:-}"

EXTRA_ARGS=()
if [[ -n "${DATASET_ROOT}" ]]; then
  EXTRA_ARGS+=(--dataset.root "${DATASET_ROOT}")
fi
if [[ -n "${FORCE_RESUME}" ]]; then
  EXTRA_ARGS+=("--resume=${FORCE_RESUME}")
fi

PYTHONPATH="${REPO_ROOT}/src${PYTHONPATH:+:$PYTHONPATH}" \
accelerate launch \
  --num_processes "${NUM_GPUS}" \
  --num_machines 1 \
  --machine_rank 0 \
  --main_process_port "${MASTER_PORT}" \
  -m lerobot.scripts.lerobot_train \
  "--config_path=${CONFIG_PATH}" \
  "${EXTRA_ARGS[@]}"
