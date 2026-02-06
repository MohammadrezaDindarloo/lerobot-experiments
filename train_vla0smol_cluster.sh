#!/usr/bin/env bash
set -euo pipefail

# Cluster/GPU training
CONFIG_PATH="${CONFIG_PATH:-configs/vla0_smol_cons_libero_custom.json}"

PYTHONPATH="$(pwd)/src${PYTHONPATH:+:$PYTHONPATH}" \
python -m lerobot.scripts.lerobot_train \
  --config_path "${CONFIG_PATH}"
