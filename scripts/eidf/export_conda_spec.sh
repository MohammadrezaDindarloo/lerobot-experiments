#!/usr/bin/env bash
set -euo pipefail

# Export a portable conda spec from macOS so it can be recreated on Linux.
# This does NOT copy binaries; it captures top-level dependencies.

ENV_NAME="${ENV_NAME:-vla0smol}"
OUT_DIR="${OUT_DIR:-docker/conda}"
OUT_FILE="${OUT_FILE:-${OUT_DIR}/${ENV_NAME}.linux.yml}"

if ! command -v conda >/dev/null 2>&1; then
  echo "[ERROR] conda not found in PATH." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

if ! conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
  echo "[ERROR] Conda env '$ENV_NAME' not found." >&2
  echo "        Available envs:" >&2
  conda env list >&2
  exit 1
fi

echo "[INFO] Exporting conda env '$ENV_NAME' to $OUT_FILE"
conda env export -n "$ENV_NAME" --from-history \
  | sed '/^prefix:/d' > "$OUT_FILE"

echo "[INFO] Export complete."
echo "[INFO] File: $OUT_FILE"
echo "[INFO] Next: build Linux image with scripts/eidf/build_push_eidf_image.sh"
