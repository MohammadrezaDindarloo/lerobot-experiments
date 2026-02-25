#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# EIDF Kubernetes setup for lerobot-experiments
#
# What this script does:
# 1) Ensures a CephFS PVC exists.
# 2) Creates a loader Job that mounts the PVC and sleeps.
# 3) Copies required repository material into /mnt/ceph/code on the PVC.
# 4) Leaves the loader pod running for additional uploads.
# ==============================================================================

NS="${NS:-eidf029ns}"
QUEUE="${QUEUE:-eidf029ns-user-queue}"
EIDF_USER="${EIDF_USER:-s2816905-infk8}"
PROJECT_NAME="${PROJECT_NAME:-lerobot-exp}"
PVC="${PVC:-${PROJECT_NAME}-pvc}"
PVC_SIZE="${PVC_SIZE:-400Gi}"
REMOTE_CODE_DIR="${REMOTE_CODE_DIR:-/mnt/ceph/code}"

LOADER_CPU="${LOADER_CPU:-1}"
LOADER_MEM="${LOADER_MEM:-1Gi}"

# Minimal set needed for train/eval on cluster.
SYNC_ITEMS_DEFAULT=(
  src
  configs
  scripts
  pyproject.toml
  requirements.in
  requirements-ubuntu.txt
  requirements-macos.txt
  MANIFEST.in
  README.md
)

log() { echo "[INFO] $*"; }

wait_for_pod_by_label() {
  local selector="$1"
  local timeout_s="${2:-180}"
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

require_item() {
  local item="$1"
  [[ -e "$item" ]] || {
    echo "[ERROR] Missing required path: $item (expected in $(pwd))"
    exit 1
  }
}

log "Namespace:      $NS"
log "Queue:          $QUEUE"
log "EIDF user:      $EIDF_USER"
log "Project name:   $PROJECT_NAME"
log "PVC:            $PVC ($PVC_SIZE)"
log "Remote code:    $REMOTE_CODE_DIR"

for item in "${SYNC_ITEMS_DEFAULT[@]}"; do
  require_item "$item"
done

if kubectl -n "$NS" get pvc "$PVC" >/dev/null 2>&1; then
  log "PVC exists: $PVC"
else
  log "Creating PVC: $PVC"
  kubectl -n "$NS" create -f - <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC
  labels:
    eidf/user: "$EIDF_USER"
    project: "$PROJECT_NAME"
spec:
  accessModes: [ReadWriteMany]
  resources:
    requests:
      storage: $PVC_SIZE
  storageClassName: csi-cephfs-sc
YAML
fi

kubectl -n "$NS" wait --for=jsonpath='{.status.phase}'=Bound pvc/"$PVC" --timeout=180s >/dev/null
log "PVC ready (Bound): $PVC"

log "Creating loader job..."
kubectl -n "$NS" create -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  generateName: ${PROJECT_NAME}-loader-
  labels:
    eidf/user: "$EIDF_USER"
    project: "$PROJECT_NAME"
    app: "${PROJECT_NAME}-loader"
    kueue.x-k8s.io/queue-name: $QUEUE
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 1800
  template:
    metadata:
      labels:
        eidf/user: "$EIDF_USER"
        project: "$PROJECT_NAME"
        app: "${PROJECT_NAME}-loader"
    spec:
      restartPolicy: Never
      containers:
      - name: loader
        image: busybox
        args: ["sleep","infinity"]
        resources:
          requests:
            cpu: ${LOADER_CPU}
            memory: "${LOADER_MEM}"
          limits:
            cpu: ${LOADER_CPU}
            memory: "${LOADER_MEM}"
        volumeMounts:
        - name: v
          mountPath: /mnt/ceph
      volumes:
      - name: v
        persistentVolumeClaim:
          claimName: $PVC
YAML

log "Waiting for loader pod..."
LOADER_POD="$(wait_for_pod_by_label "app=${PROJECT_NAME}-loader" 180)" || {
  echo "[ERROR] Loader pod did not appear."
  kubectl -n "$NS" get events --sort-by=.lastTimestamp | tail -n 30
  exit 1
}
log "Loader pod: $LOADER_POD"

log "Waiting for loader pod to become Ready..."
until kubectl -n "$NS" get pod "$LOADER_POD" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q True
 do
  PHASE=$(kubectl -n "$NS" get pod "$LOADER_POD" -o jsonpath='{.status.phase}' 2>/dev/null)
  log "Loader pod not ready yet (phase=$PHASE)..."
  sleep 15
 done

log "Preparing destination directories on PVC..."
kubectl -n "$NS" exec "$LOADER_POD" -- sh -lc "rm -rf '${REMOTE_CODE_DIR}' && mkdir -p '${REMOTE_CODE_DIR}' /mnt/ceph/outputs /mnt/ceph/.cache"

log "Copying repository material to PVC..."
tar -cf - "${SYNC_ITEMS_DEFAULT[@]}" | kubectl -n "$NS" exec -i "$LOADER_POD" -- sh -lc "tar -C '${REMOTE_CODE_DIR}' -xf -"

log "PVC code snapshot:"
kubectl -n "$NS" exec "$LOADER_POD" -- sh -lc "ls -lah '${REMOTE_CODE_DIR}'"

log ""
log "=========================================="
log " Setup complete"
log "=========================================="
log "Loader pod:  $LOADER_POD"
log "PVC:         $PVC"
log "Code on PVC: ${REMOTE_CODE_DIR}"
log ""
log "Upload extra files (datasets/configs):"
log "  kubectl -n $NS cp <local-path> ${LOADER_POD}:${REMOTE_CODE_DIR}/<dest>"
log ""
log "Next step:"
log "  ./run_train.sh"
log "=========================================="
