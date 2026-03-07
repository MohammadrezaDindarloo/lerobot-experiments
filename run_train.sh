#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# EIDF Kubernetes train job for lerobot-experiments
# ==============================================================================

NS="${NS:-eidf029ns}"
QUEUE="${QUEUE:-eidf029ns-user-queue}"
EIDF_USER="${EIDF_USER:-s2816905-infk8}"
PROJECT_NAME="${PROJECT_NAME:-lerobot-exp}"
PVC="${PVC:-${PROJECT_NAME}-pvc}"
IMAGE="${IMAGE:-docker.io/mohammadrezadindarloo/lerobot-vla0smol:latest}"
REMOTE_CODE_DIR="${REMOTE_CODE_DIR:-/mnt/ceph/code}"

TRAIN_CPU="${TRAIN_CPU:-6}"
TRAIN_MEM="${TRAIN_MEM:-96Gi}"
TRAIN_GPU="${TRAIN_GPU:-4}"
GPU_PRODUCT="${GPU_PRODUCT:-NVIDIA-A100-SXM4-40GB}"
SHM_SIZE="${SHM_SIZE:-16Gi}"

NUM_GPUS="${NUM_GPUS:-$TRAIN_GPU}"
MASTER_PORT="${MASTER_PORT:-29500}"
CONFIG_PATH="${CONFIG_PATH:-/mnt/ceph/code/configs/vla0_smol_libero_custom.json}"
DATASET_ROOT="${DATASET_ROOT:-}"
OUTPUT_DIR="${OUTPUT_DIR:-/mnt/ceph/outputs/train}"
RUN_NAME="${RUN_NAME:-eidf-$(date +%Y%m%d-%H%M%S)}"

# Dependency strategy
INSTALL_DEPS="${INSTALL_DEPS:-1}"                 # 1=yes, 0=no
# Include LIBERO + vla0_smol extras by default for this workflow.
INSTALL_CMD="${INSTALL_CMD:-pip install --no-cache-dir -e .\[libero,vla0_smol\]}"
FORCE_TRANSFORMERS_COMPAT="${FORCE_TRANSFORMERS_COMPAT:-1}"
PREINSTALL_BUILD_TOOLS="${PREINSTALL_BUILD_TOOLS:-1}"
BUILD_TOOLS_CMD="${BUILD_TOOLS_CMD:-pip install --no-cache-dir cmake ninja}"
USE_CREDENTIALS_SECRET="${USE_CREDENTIALS_SECRET:-1}"
CREDENTIALS_SECRET_NAME="${CREDENTIALS_SECRET_NAME:-ml-credentials}"
SUBMIT_ONLY="${SUBMIT_ONLY:-1}"                 # 1=submit and exit, 0=submit/wait/stream logs
DISABLE_EVAL="${DISABLE_EVAL:-0}"               # 1=disable in-training eval

log() { echo "[INFO] $*"; }

wait_for_pod_by_label() {
  local selector="$1"
  local timeout_s="${2:-240}"
  local interval_s=2
  local waited=0

  while (( waited < timeout_s )); do
    local pod
    pod="$(kubectl -n "$NS" get pods -l "$selector" \
      --sort-by=.metadata.creationTimestamp \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | tail -n 1 || true)"
    if [[ -n "$pod" ]]; then
      echo "$pod"
      return 0
    fi
    sleep "$interval_s"
    waited=$(( waited + interval_s ))
  done

  return 1
}

wait_for_container_start() {
  local pod="$1"
  local container="$2"
  local timeout_s="${3:-420}"
  local interval_s=3
  local waited=0

  while (( waited < timeout_s )); do
    if kubectl -n "$NS" logs "$pod" -c "$container" --tail=1 >/dev/null 2>&1; then
      return 0
    fi
    sleep "$interval_s"
    waited=$(( waited + interval_s ))
  done

  return 1
}

log "Namespace:      $NS"
log "Queue:          $QUEUE"
log "Project name:   $PROJECT_NAME"
log "PVC:            $PVC"
log "Image:          $IMAGE"
log "Code dir:       $REMOTE_CODE_DIR"
log "Config:         $CONFIG_PATH"
log "Output base:    $OUTPUT_DIR"
log "Run name:       $RUN_NAME"
log "Resources:      CPU=$TRAIN_CPU MEM=$TRAIN_MEM GPU=$TRAIN_GPU"
log "Shared memory:  $SHM_SIZE"
log "GPU product:    $GPU_PRODUCT"
log "Install deps:   $INSTALL_DEPS"
log "TF compat fix:  $FORCE_TRANSFORMERS_COMPAT"
log "Build tools:    $PREINSTALL_BUILD_TOOLS"
log "Use secret:     $USE_CREDENTIALS_SECRET (name=${CREDENTIALS_SECRET_NAME})"
log "Submit only:    $SUBMIT_ONLY"
log "Disable eval:   $DISABLE_EVAL"

if ! kubectl -n "$NS" get pvc "$PVC" >/dev/null 2>&1; then
  echo "[ERROR] PVC '$PVC' not found. Run ./run_setup.sh first."
  exit 1
fi

if [[ "$USE_CREDENTIALS_SECRET" == "1" ]]; then
  if ! kubectl -n "$NS" get secret "$CREDENTIALS_SECRET_NAME" >/dev/null 2>&1; then
    echo "[ERROR] Secret '$CREDENTIALS_SECRET_NAME' not found in namespace '$NS'."
    echo "        Create it first or run with USE_CREDENTIALS_SECRET=0."
    exit 1
  fi
fi

DATASET_ARG=""
if [[ -n "$DATASET_ROOT" ]]; then
  DATASET_ARG="--dataset.root=${DATASET_ROOT}"
fi

EVAL_ARG=""
if [[ "$DISABLE_EVAL" == "1" ]]; then
  # Keep eval effectively disabled while preserving training behavior.
  EVAL_ARG="--eval_freq=999999999"
fi

log "Creating training job..."
ENV_SECRET_BLOCK=""
if [[ "$USE_CREDENTIALS_SECRET" == "1" ]]; then
  ENV_SECRET_BLOCK=$(cat <<EOF
        env:
        - name: HF_TOKEN
          valueFrom:
            secretKeyRef:
              name: ${CREDENTIALS_SECRET_NAME}
              key: HF_TOKEN
        - name: HUGGING_FACE_HUB_TOKEN
          valueFrom:
            secretKeyRef:
              name: ${CREDENTIALS_SECRET_NAME}
              key: HF_TOKEN
        - name: WANDB_API_KEY
          valueFrom:
            secretKeyRef:
              name: ${CREDENTIALS_SECRET_NAME}
              key: WANDB_API_KEY
EOF
)
fi

JOB_REF="$(kubectl -n "$NS" create -f - -o name <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  generateName: ${PROJECT_NAME}-train-
  labels:
    eidf/user: "$EIDF_USER"
    project: "$PROJECT_NAME"
    app: "${PROJECT_NAME}-train"
    kueue.x-k8s.io/queue-name: $QUEUE
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 18000
  template:
    metadata:
      labels:
        eidf/user: "$EIDF_USER"
        project: "$PROJECT_NAME"
        app: "${PROJECT_NAME}-train"
    spec:
      nodeSelector:
        nvidia.com/gpu.product: "${GPU_PRODUCT}"
      restartPolicy: Never
      containers:
      - name: trainer
        image: $IMAGE
        workingDir: $REMOTE_CODE_DIR
${ENV_SECRET_BLOCK}
        command: ["/bin/bash","-lc"]
        args:
          - |
            set -e
            echo "=== Runtime info ==="
            pwd
            ls -lah
            nvidia-smi || true

            export HF_HOME=/mnt/ceph/.cache/huggingface
            export TRANSFORMERS_CACHE=/mnt/ceph/.cache/huggingface
            export PYTHONPATH="${REMOTE_CODE_DIR}/src:\${PYTHONPATH:-}"
            export LIBERO_CONFIG_PATH="\${LIBERO_CONFIG_PATH:-/mnt/ceph/.libero}"
            export LIBERO_DATASETS_DIR="\${LIBERO_DATASETS_DIR:-/mnt/ceph/datasets/libero}"

            mkdir -p /mnt/ceph/outputs /mnt/ceph/.cache/huggingface "\$LIBERO_CONFIG_PATH" "\$LIBERO_DATASETS_DIR"

            # Avoid interactive LIBERO setup prompt in non-interactive Kubernetes jobs.
            python3 - <<'PY'
            import os
            import sys
            from pathlib import Path

            cfg_dir = Path(os.environ.get("LIBERO_CONFIG_PATH", "/mnt/ceph/.libero"))
            cfg_file = cfg_dir / "config.yaml"
            dataset_dir = Path(os.environ.get("LIBERO_DATASETS_DIR", "/mnt/ceph/datasets/libero"))
            dataset_dir.mkdir(parents=True, exist_ok=True)

            if cfg_file.exists():
                print(f"Using existing LIBERO config: {cfg_file}")
                raise SystemExit(0)

            libero_root = None
            for path_entry in map(Path, sys.path):
                candidate = path_entry / "libero" / "libero"
                if (candidate / "__init__.py").exists():
                    libero_root = candidate
                    break

            if libero_root is None:
                print("[ERROR] Could not locate libero package path on sys.path.", file=sys.stderr)
                raise SystemExit(1)

            cfg_dir.mkdir(parents=True, exist_ok=True)
            cfg_file.write_text(
                "\n".join(
                    [
                        f"benchmark_root: {libero_root}",
                        f"bddl_files: {libero_root / 'bddl_files'}",
                        f"init_states: {libero_root / 'init_files'}",
                        f"datasets: {dataset_dir}",
                        f"assets: {libero_root / 'assets'}",
                        "",
                    ]
                )
            )
            print(f"Initialized LIBERO config: {cfg_file}")
            PY

            if [[ "${INSTALL_DEPS}" == "1" ]]; then
              echo "=== Installing dependencies ==="
              if [[ "${PREINSTALL_BUILD_TOOLS}" == "1" ]]; then
                # Needed by LIBERO deps such as egl_probe / hf-egl-probe.
                ${BUILD_TOOLS_CMD}
              fi
              if [[ "${FORCE_TRANSFORMERS_COMPAT}" == "1" ]]; then
                # The base HF image can ship a transformers dev checkout that requires
                # huggingface-hub==1.0.0.rc*, which conflicts with lerobot constraints.
                pip uninstall -y transformers || true
                pip install --no-cache-dir "huggingface-hub>=0.34.2,<0.36.0" "transformers>=4.53.0,<5.0.0"
              fi
              ${INSTALL_CMD}
            else
              echo "=== Skipping dependency installation ==="
            fi

            echo "=== Training ==="
            accelerate launch \
              --num_processes "${NUM_GPUS}" \
              --num_machines 1 \
              --machine_rank 0 \
              --main_process_port "${MASTER_PORT}" \
              -m lerobot.scripts.lerobot_train \
              "--config_path=${CONFIG_PATH}" \
              "--output_dir=${OUTPUT_DIR}/${RUN_NAME}" \
              ${DATASET_ARG} \
              ${EVAL_ARG}
        resources:
          requests:
            cpu: ${TRAIN_CPU}
            memory: "${TRAIN_MEM}"
          limits:
            cpu: ${TRAIN_CPU}
            memory: "${TRAIN_MEM}"
            nvidia.com/gpu: ${TRAIN_GPU}
        volumeMounts:
        - name: v
          mountPath: /mnt/ceph
        - name: dshm
          mountPath: /dev/shm
      volumes:
      - name: v
        persistentVolumeClaim:
          claimName: $PVC
      - name: dshm
        emptyDir:
          medium: Memory
          sizeLimit: "${SHM_SIZE}"
YAML
)"

JOB_NAME="${JOB_REF#job.batch/}"
log "Created job:    ${JOB_NAME}"

if [[ "$SUBMIT_ONLY" == "1" ]]; then
  log "Submit-only mode: exiting without waiting for pod/logs."
  log "Watch job:      kubectl -n $NS get job ${JOB_NAME} -w"
  log "Follow logs:    kubectl -n $NS logs -f job/${JOB_NAME} -c trainer"
  exit 0
fi

log "Waiting for training pod..."
TRAIN_POD="$(wait_for_pod_by_label "app=${PROJECT_NAME}-train" 300)" || {
  echo "[ERROR] Training pod did not appear."
  kubectl -n "$NS" get events --sort-by=.lastTimestamp | tail -n 30
  exit 1
}

log "Training pod: $TRAIN_POD"

if ! wait_for_container_start "$TRAIN_POD" "trainer" 480; then
  echo "[ERROR] Trainer container did not start."
  kubectl -n "$NS" get pod "$TRAIN_POD" -o wide
  kubectl -n "$NS" describe pod "$TRAIN_POD" | sed -n '/Events:/,$p'
  exit 1
fi

log "Streaming training logs..."
kubectl -n "$NS" logs -f "$TRAIN_POD" -c trainer

log "Training completed. Outputs should be under ${OUTPUT_DIR}/${RUN_NAME}."
