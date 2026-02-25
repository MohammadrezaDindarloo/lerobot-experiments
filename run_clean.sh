#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Cleanup EIDF resources for lerobot-experiments
# ==============================================================================

NS="${NS:-eidf029ns}"
EIDF_USER="${EIDF_USER:-s2816905-infk8}"
PROJECT_NAME="${PROJECT_NAME:-lerobot-exp}"
PVC="${PVC:-${PROJECT_NAME}-pvc}"
DELETE_PVC="${DELETE_PVC:-0}"

log() { echo "[INFO] $*"; }

SELECTOR="eidf/user=${EIDF_USER},project=${PROJECT_NAME}"

log "Namespace:      $NS"
log "EIDF user:      $EIDF_USER"
log "Project name:   $PROJECT_NAME"
log "PVC:            $PVC"
log "DELETE_PVC:     $DELETE_PVC"

log "Deleting Jobs and Pods with selector: $SELECTOR"
kubectl -n "$NS" delete job -l "$SELECTOR" --ignore-not-found=true
kubectl -n "$NS" delete pod -l "$SELECTOR" --ignore-not-found=true

if [[ "$DELETE_PVC" == "1" ]]; then
  log "Deleting PVC: $PVC"
  kubectl -n "$NS" delete pvc "$PVC" --ignore-not-found=true
else
  log "PVC kept. Set DELETE_PVC=1 to delete it."
fi

log "Remaining resources for selector:"
kubectl -n "$NS" get jobs,pods,pvc -l "$SELECTOR" -o wide || true
