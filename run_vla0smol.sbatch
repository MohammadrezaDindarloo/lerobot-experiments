#!/bin/bash
#SBATCH --job-name=vla0smol
#SBATCH --partition=PGR-Standard
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --output=%x-%j.out
#SBATCH --error=%x-%j.err

set -euo pipefail

# Start in the directory you submitted from
cd "$SLURM_SUBMIT_DIR"

echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "Start time: $(date)"

# Show what GPU Slurm gave you (useful for debugging)
echo "CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-<unset>}"
echo "SLURM_JOB_GPUS=${SLURM_JOB_GPUS:-<unset>}"
echo "SLURM_STEP_GPUS=${SLURM_STEP_GPUS:-<unset>}"
nvidia-smi || true

# Activate conda
if [ -x /opt/conda/bin/conda ]; then
  eval "$(/opt/conda/bin/conda shell.bash hook)"
else
  # fallback if conda is initialized via your shell startup files
  source ~/.bashrc
fi
conda activate vla0smol

# (Optional) re-check after env activation
echo "After conda: CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-<unset>}"
nvidia-smi || true

# Pick a cache/work directory that exists (avoid AFS quota)
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

# Rendering setup for MuJoCo/robosuite headless
export MUJOCO_GL=egl
export PYOPENGL_PLATFORM=egl

# Go to your repo
cd /home/s2816905/repos/lerobot-experiments

# Run your script
chmod +x vla0smol.sh
./vla0smol.sh

echo "End time: $(date)"
