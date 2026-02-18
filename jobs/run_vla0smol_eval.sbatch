#!/bin/bash
#SBATCH --job-name=vla0smol-eval
#SBATCH --partition=PGR-Standard
#SBATCH --nodelist=herman
#SBATCH --gres=gpu:h200:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=02:00:00
#SBATCH --output=logs/%x/%x-%j.out
#SBATCH --error=logs/%x/%x-%j.err
#SBATCH --mail-user=s2816905@ed.ac.uk
#SBATCH --mail-type=BEGIN,END,FAIL

set -euo pipefail

export HF_HUB_ENABLE_HF_TRANSFER=1
# Optional: set your HF token here on the cluster (or use `huggingface-cli login`)
# export HF_TOKEN=""

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

# Fail fast if CUDA is not available in this environment
python - <<'PY'
import torch
print("torch", torch.__version__)
print("cuda available:", torch.cuda.is_available())
print("cuda devices:", torch.cuda.device_count())
if not torch.cuda.is_available():
    raise SystemExit("CUDA is not available in this environment.")
PY

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

export MUJOCO_GL=egl
export PYOPENGL_PLATFORM=egl

cd /home/s2816905/repos/lerobot-experiments

chmod +x scripts/cluster/eval_vla0smol_cluster.sh
./scripts/cluster/eval_vla0smol_cluster.sh

echo "End time: $(date)"
