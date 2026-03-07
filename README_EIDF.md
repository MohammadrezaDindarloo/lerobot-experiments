# lerobot-experiments on EIDF (Kubernetes)

This runbook adapts `lerobot-experiments` from Slurm workflows to EIDF Kubernetes Jobs.

## Files added

- `run_setup.sh`: create PVC, start loader pod, copy repository material to `/mnt/ceph/code`
- `run_train.sh`: submit GPU training job via `accelerate` + `lerobot_train`
- `run_eval.sh`: submit GPU evaluation job via `lerobot_eval`
- `run_fetch.sh`: fetch `/mnt/ceph/outputs` from PVC to local `./outputs`
- `run_clean.sh`: cleanup jobs/pods and optional PVC

## Quick start

```bash
chmod +x run_setup.sh run_train.sh run_eval.sh run_fetch.sh run_clean.sh

./run_setup.sh
./run_train.sh
./run_eval.sh
./run_fetch.sh
```

## Key environment variables

Shared:

- `NS` (default `eidf029ns`)
- `QUEUE` (default `eidf029ns-user-queue`)
- `EIDF_USER` (default `s2816905-infk8`)
- `PROJECT_NAME` (default `lerobot-exp`)
- `PVC` (default `${PROJECT_NAME}-pvc`)

Training:

- `CONFIG_PATH` default `/mnt/ceph/code/configs/vla0_smol_libero_custom.json`
- `DATASET_ROOT` optional dataset root on PVC
- `OUTPUT_DIR` default `/mnt/ceph/outputs/train`
- `TRAIN_GPU`, `GPU_PRODUCT`
- `INSTALL_DEPS` (default `1`) and `INSTALL_CMD` (default `pip -q install --no-cache-dir -e .`)

Evaluation:

- `POLICY_PATH` (local PVC checkpoint path or HF repo id). If empty, script picks latest PVC checkpoint.
- `ENV_TYPE` / `ENV_TASK`
- `EVAL_EPISODES`, `EVAL_BATCH_SIZE`
- `OUTPUT_DIR` default `/mnt/ceph/outputs/eval`

Cleanup:

```bash
./run_clean.sh
DELETE_PVC=1 ./run_clean.sh
```

## Notes

- These scripts assume code is mounted from PVC at `/mnt/ceph/code` and outputs are written under `/mnt/ceph/outputs`.
- Dependency install happens inside train/eval jobs by default for reproducibility (`INSTALL_DEPS=1`).

## Use your local Conda env in EIDF image

You cannot copy a macOS Conda environment binary directly into Linux.
Instead, export a portable environment spec from your local env, build a Linux image from it, and run jobs with `INSTALL_DEPS=0`.

### 1) Export local env to Linux-portable spec

If your local env is `vla0smol`:

```bash
ENV_NAME=vla0smol scripts/eidf/export_conda_spec.sh
```

This writes:

- `docker/conda/vla0smol.linux.yml`

### 2) Build and push Linux image

Set your container registry/repo, login first (`docker login ...`), then:

```bash
IMAGE_REPO=ghcr.io/<your-user>/lerobot-vla0smol \
IMAGE_TAG=latest \
CONDA_ENV_NAME=vla0smol \
CONDA_ENV_FILE=docker/conda/vla0smol.linux.yml \
scripts/eidf/build_push_eidf_image.sh
```

Notes:
- Default build platform is `linux/amd64` (good for A100 nodes).
- If your cluster requires a different architecture, set `PLATFORM=...`.
- The image build installs project deps by default with:
  - `python -m pip install --no-cache-dir -e .[libero,vla0_smol]`
- Override with `PIP_INSTALL_CMD='...'` if needed.

### 3) Run EIDF jobs using that image

Training:

```bash
IMAGE=ghcr.io/<your-user>/lerobot-vla0smol:latest INSTALL_DEPS=0 ./run_train.sh
```

Evaluation:

```bash
IMAGE=ghcr.io/<your-user>/lerobot-vla0smol:latest INSTALL_DEPS=0 ./run_eval.sh
```
