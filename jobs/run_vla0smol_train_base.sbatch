#!/bin/bash
#SBATCH --job-name=vla0smol-base
#SBATCH --partition=PGR-Standard
#SBATCH --nodelist=herman
#SBATCH --gres=gpu:h200:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=10:00:00
#SBATCH --output=logs/%x/%x-%j.out
#SBATCH --error=logs/%x/%x-%j.err

set -euo pipefail

export HF_HUB_ENABLE_HF_TRANSFER=1
# Optional: set your HF token here on the cluster (or use `huggingface-cli login`)
# export HF_TOKEN="hf_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

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

WORKDIR="/work/$USER"
if [ ! -d "$WORKDIR" ]; then
  WORKDIR="/tmp/$USER"
fi
mkdir -p "$WORKDIR"/cache/{huggingface,torch}

export HF_HOME="$WORKDIR/cache/huggingface"
export TORCH_HOME="$WORKDIR/cache/torch"
export XDG_CACHE_HOME="$WORKDIR/cache"
export TRANSFORMERS_CACHE="$HF_HOME"
export HF_HUB_CACHE="$HF_HOME/hub"

export MUJOCO_GL=egl
export PYOPENGL_PLATFORM=egl

cd /home/s2816905/repos/lerobot-experiments

chmod +x scripts/cluster/train_vla0smol_base.sh
CONFIG_PATH=configs/vla0_smol_libero_custom.json ./scripts/cluster/train_vla0smol_base.sh

echo "End time: $(date)"
