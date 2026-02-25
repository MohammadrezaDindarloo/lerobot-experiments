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
