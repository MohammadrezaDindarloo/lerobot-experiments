#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Fetch /mnt/ceph/outputs from PVC to local ./outputs
# ==============================================================================

NS="${NS:-eidf029ns}"
PROJECT_NAME="${PROJECT_NAME:-lerobot-exp}"
EIDF_USER="${EIDF_USER:-s2816905-infk8}"
PVC="${PVC:-${PROJECT_NAME}-pvc}"

REMOTE_OUTPUT_DIR="/mnt/ceph/outputs"
LOCAL_OUTPUT_DIR="./outputs"

log() { echo "[INFO] $*"; }

log "Looking for existing loader pod..."
LOADER_POD="$(kubectl -n "$NS" get pods \
  -l app=${PROJECT_NAME}-loader \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"

TEMP_LOADER=0

if [[ -z "$LOADER_POD" ]]; then
  log "No running loader pod found. Creating a temporary fetch pod..."
  LOADER_POD="$(kubectl -n "$NS" create -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  generateName: ${PROJECT_NAME}-fetch-
  labels:
    eidf/user: "$EIDF_USER"
    project: "$PROJECT_NAME"
    app: "${PROJECT_NAME}-fetch"
spec:
  restartPolicy: Never
  containers:
  - name: fetcher
    image: busybox
    command: ["sh","-c","sleep 3600"]
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "100m"
        memory: "128Mi"
    volumeMounts:
    - name: v
      mountPath: /mnt/ceph
  volumes:
  - name: v
    persistentVolumeClaim:
      claimName: $PVC
YAML
  | sed -n 's/.*pod\/\([^ ]*\).*/\1/p')"

  TEMP_LOADER=1
  kubectl -n "$NS" wait --for=condition=Ready pod/"$LOADER_POD" --timeout=120s >/dev/null
else
  log "Using existing loader pod: $LOADER_POD"
fi

mkdir -p "$LOCAL_OUTPUT_DIR"
log "Fetching outputs from PVC..."
kubectl -n "$NS" cp "$LOADER_POD":"$REMOTE_OUTPUT_DIR/." "$LOCAL_OUTPUT_DIR"
log "Outputs fetched to: $LOCAL_OUTPUT_DIR"

if [[ "$TEMP_LOADER" == "1" ]]; then
  log "Deleting temporary fetch pod..."
  kubectl -n "$NS" delete pod "$LOADER_POD" --ignore-not-found=true
fi

log "Fetch completed successfully."
