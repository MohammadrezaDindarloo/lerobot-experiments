#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# EIDF Kubernetes eval job for lerobot-experiments
# ==============================================================================

NS="${NS:-eidf029ns}"
QUEUE="${QUEUE:-eidf029ns-user-queue}"
EIDF_USER="${EIDF_USER:-s2816905-infk8}"
PROJECT_NAME="${PROJECT_NAME:-lerobot-exp}"
PVC="${PVC:-${PROJECT_NAME}-pvc}"
IMAGE="${IMAGE:-huggingface/transformers-pytorch-gpu:latest}"
REMOTE_CODE_DIR="${REMOTE_CODE_DIR:-/mnt/ceph/code}"

EVAL_CPU="${EVAL_CPU:-4}"
EVAL_MEM="${EVAL_MEM:-16Gi}"
EVAL_GPU="${EVAL_GPU:-4}"
GPU_PRODUCT="${GPU_PRODUCT:-NVIDIA-A100-SXM4-40GB}"

ENV_TYPE="${ENV_TYPE:-libero}"
ENV_TASK="${ENV_TASK:-libero_object}"
EVAL_BATCH_SIZE="${EVAL_BATCH_SIZE:-1}"
EVAL_EPISODES="${EVAL_EPISODES:-16}"
OUTPUT_DIR="${OUTPUT_DIR:-/mnt/ceph/outputs/eval}"
RUN_NAME="${RUN_NAME:-eidf-$(date +%Y%m%d-%H%M%S)}"

INSTALL_DEPS="${INSTALL_DEPS:-1}"
# Include LIBERO + vla0_smol extras by default for this workflow.
INSTALL_CMD="${INSTALL_CMD:-pip install --no-cache-dir -e .\[libero,vla0_smol\]}"
FORCE_TRANSFORMERS_COMPAT="${FORCE_TRANSFORMERS_COMPAT:-1}"
PREINSTALL_BUILD_TOOLS="${PREINSTALL_BUILD_TOOLS:-1}"
BUILD_TOOLS_CMD="${BUILD_TOOLS_CMD:-pip install --no-cache-dir cmake ninja}"
USE_CREDENTIALS_SECRET="${USE_CREDENTIALS_SECRET:-1}"
CREDENTIALS_SECRET_NAME="${CREDENTIALS_SECRET_NAME:-ml-credentials}"

log() { echo "[INFO] $*"; }

wait_for_pod_by_label() {
  local selector="$1"
  local timeout_s="${2:-300}"
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

if ! kubectl -n "$NS" get pvc "$PVC" >/dev/null 2>&1; then
  echo "[ERROR] PVC '$PVC' not found. Run ./run_setup.sh first."
  exit 1
fi

POLICY_PATH="${POLICY_PATH:-}"

log "Namespace:      $NS"
log "Queue:          $QUEUE"
log "Project name:   $PROJECT_NAME"
log "PVC:            $PVC"
log "Image:          $IMAGE"
log "Code dir:       $REMOTE_CODE_DIR"
log "Env:            ${ENV_TYPE}/${ENV_TASK}"
log "Eval episodes:  $EVAL_EPISODES"
log "Eval batch:     $EVAL_BATCH_SIZE"
log "Install deps:   $INSTALL_DEPS"
log "TF compat fix:  $FORCE_TRANSFORMERS_COMPAT"
log "Build tools:    $PREINSTALL_BUILD_TOOLS"
log "Use secret:     $USE_CREDENTIALS_SECRET (name=${CREDENTIALS_SECRET_NAME})"

log "Creating evaluation job..."
if [[ "$USE_CREDENTIALS_SECRET" == "1" ]]; then
  if ! kubectl -n "$NS" get secret "$CREDENTIALS_SECRET_NAME" >/dev/null 2>&1; then
    echo "[ERROR] Secret '$CREDENTIALS_SECRET_NAME' not found in namespace '$NS'."
    echo "        Create it first or run with USE_CREDENTIALS_SECRET=0."
    exit 1
  fi
fi

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

kubectl -n "$NS" create -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  generateName: ${PROJECT_NAME}-eval-
  labels:
    eidf/user: "$EIDF_USER"
    project: "$PROJECT_NAME"
    app: "${PROJECT_NAME}-eval"
    kueue.x-k8s.io/queue-name: $QUEUE
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 1800
  template:
    metadata:
      labels:
        eidf/user: "$EIDF_USER"
        project: "$PROJECT_NAME"
        app: "${PROJECT_NAME}-eval"
    spec:
      nodeSelector:
        nvidia.com/gpu.product: "${GPU_PRODUCT}"
      restartPolicy: Never
      containers:
      - name: evaluator
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

            if [[ -z "${POLICY_PATH}" ]]; then
              POLICY_PATH=$(ls -td /mnt/ceph/outputs/train/*/checkpoints/last/pretrained_model 2>/dev/null | head -n 1 || true)
            fi

            if [[ -z "${POLICY_PATH}" ]]; then
              echo "No policy checkpoint found. Set POLICY_PATH to a local PVC path or HF repo id." >&2
              exit 1
            fi

            echo "=== Evaluating policy: ${POLICY_PATH} ==="
            python -m lerobot.scripts.lerobot_eval \
              "--policy.path=${POLICY_PATH}" \
              "--env.type=${ENV_TYPE}" \
              "--env.task=${ENV_TASK}" \
              "--eval.batch_size=${EVAL_BATCH_SIZE}" \
              "--eval.n_episodes=${EVAL_EPISODES}" \
              "--output_dir=${OUTPUT_DIR}/${RUN_NAME}"
        resources:
          requests:
            cpu: ${EVAL_CPU}
            memory: "${EVAL_MEM}"
          limits:
            cpu: ${EVAL_CPU}
            memory: "${EVAL_MEM}"
            nvidia.com/gpu: ${EVAL_GPU}
        volumeMounts:
        - name: v
          mountPath: /mnt/ceph
      volumes:
      - name: v
        persistentVolumeClaim:
          claimName: $PVC
YAML

log "Waiting for evaluation pod..."
EVAL_POD="$(wait_for_pod_by_label "app=${PROJECT_NAME}-eval" 300)" || {
  echo "[ERROR] Evaluation pod did not appear."
  kubectl -n "$NS" get events --sort-by=.lastTimestamp | tail -n 30
  exit 1
}

log "Evaluation pod: $EVAL_POD"

if ! wait_for_container_start "$EVAL_POD" "evaluator" 480; then
  echo "[ERROR] Evaluator container did not start."
  kubectl -n "$NS" get pod "$EVAL_POD" -o wide
  kubectl -n "$NS" describe pod "$EVAL_POD" | sed -n '/Events:/,$p'
  exit 1
fi

log "Streaming evaluation logs..."
kubectl -n "$NS" logs -f "$EVAL_POD" -c evaluator

log "Evaluation completed. Outputs should be under ${OUTPUT_DIR}/${RUN_NAME}."
