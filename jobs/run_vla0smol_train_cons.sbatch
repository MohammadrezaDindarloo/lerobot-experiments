#!/bin/bash
#SBATCH --job-name=vla0smol-cons
#SBATCH --partition=PGR-Standard
#SBATCH --gres=gpu:nvidia_l40s:2
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=20:00:00
#SBATCH --output=logs/%x/%x-%j.out
#SBATCH --error=logs/%x/%x-%j.err
#SBATCH --mail-user=s2816905@ed.ac.uk
#SBATCH --mail-type=BEGIN,END,FAIL

set -euo pipefail

export HF_HUB_ENABLE_HF_TRANSFER=1
# Optional: set your HF token here on the cluster (or use `huggingface-cli login`)
export HF_TOKEN=""
export NUM_GPUS=2

cd "$SLURM_SUBMIT_DIR"

mkdir -p logs
mkdir -p logs/$SLURM_JOB_NAME

echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "Start time: $(date)"

echo "CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-<unset>}"
echo "SLURM_JOB_GPUS=${SLURM_JOB_GPUS:-<unset>}"
echo "SLURM_STEP_GPUS=${SLURM_STEP_GPUS:-<unset>}"
nvidia-smi || true

if [ -x /opt/conda/bin/conda ]; then
  eval "$(/opt/conda/bin/conda shell.bash hook)"
else
  source ~/.bashrc
fi
conda activate vla0smol

echo "After conda: CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-<unset>}"
nvidia-smi || true

# Fail fast if CUDA is not available inside a Slurm step.
srun --ntasks=1 --gpus-per-task=2 --cpus-per-task="${SLURM_CPUS_PER_TASK:-1}" python -c '
import sys
import torch
print("torch", torch.__version__)
print("cuda available:", torch.cuda.is_available())
print("cuda devices:", torch.cuda.device_count())
if not torch.cuda.is_available():
    sys.exit("CUDA is not available in this environment.")
'

WORKDIR=""
for CAND in "/work/$USER" "/lustre/$USER" "/disk/scratch/$USER" "/tmp/$USER"; do
  if [ -d "$CAND" ] || mkdir -p "$CAND" 2>/dev/null; then
    WORKDIR="$CAND"
    break
  fi
done
if [ -z "$WORKDIR" ]; then
  echo "No writable workdir found." >&2
  exit 1
fi
mkdir -p "$WORKDIR"/cache/{huggingface,torch,datasets} "$WORKDIR"/tmp

export HF_HOME="$WORKDIR/cache/huggingface"
export TORCH_HOME="$WORKDIR/cache/torch"
export XDG_CACHE_HOME="$WORKDIR/cache"
export TRANSFORMERS_CACHE="$HF_HOME"
export HF_HUB_CACHE="$HF_HOME/hub"
export HF_DATASETS_CACHE="$WORKDIR/cache/datasets"
export DATASETS_CACHE="$WORKDIR/cache/datasets"
export TMPDIR="$WORKDIR/tmp"
export DATASET_ROOT="${DATASET_ROOT:-/home/s2816905/datasets/HuggingFaceVLA_libero}"

mkdir -p "$DATASET_ROOT"
echo "DATASET_ROOT=$DATASET_ROOT"

export MUJOCO_GL=egl
export PYOPENGL_PLATFORM=egl

cd /home/s2816905/repos/lerobot-experiments

chmod +x scripts/cluster/train_vla0smol_cons.sh
MAIN_CONFIG="configs/vla0_smol_cons_libero_custom.json"
CONFIG_TO_USE="$MAIN_CONFIG"
readarray -t _RESUME_INFO < <(python - "$MAIN_CONFIG" <<'PY'
import json, pathlib, sys
cfg = json.loads(pathlib.Path(sys.argv[1]).read_text())
print("true" if bool(cfg.get("resume", False)) else "false")
print("" if cfg.get("checkpoint_path") is None else str(cfg.get("checkpoint_path")))
PY
)
CFG_RESUME="${_RESUME_INFO[0]:-false}"
CFG_CKPT_PATH="${_RESUME_INFO[1]:-}"
if [[ "$CFG_RESUME" == "true" ]]; then
  if [[ -z "$CFG_CKPT_PATH" ]]; then
    echo "resume=true but checkpoint_path is missing in $MAIN_CONFIG" >&2
    exit 1
  fi
  if [[ "$CFG_CKPT_PATH" == */train_config.json ]]; then
    CONFIG_TO_USE="$CFG_CKPT_PATH"
  else
    CONFIG_TO_USE="$CFG_CKPT_PATH/pretrained_model/train_config.json"
  fi
fi
echo "Using CONFIG_PATH=$CONFIG_TO_USE"
FORCE_RESUME_ENV=""
if [[ "$CFG_RESUME" == "true" ]]; then
  FORCE_RESUME_ENV="FORCE_RESUME=true"
fi
srun --ntasks=1 --gpus-per-task=2 --cpus-per-task="${SLURM_CPUS_PER_TASK:-1}" \
  env CONFIG_PATH="$CONFIG_TO_USE" $FORCE_RESUME_ENV ./scripts/cluster/train_vla0smol_cons.sh

echo "End time: $(date)"
