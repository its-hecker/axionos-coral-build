#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../config.env
source lib.sh
require_source_root

KDIR="$SOURCE_ROOT/$KERNEL_TREE_PATH"
COMPAT_C="$KDIR/drivers/kernelsu/kernel_compat.c"

if [[ ! -f "$COMPAT_C" ]]; then
  warn "drivers/kernelsu/kernel_compat.c not found -- skipping ksu_access_ok fix"
  exit 0
fi

FLAG_FILE="$KDIR/.ksu-access-ok-dedupe-applied"
if [[ -f "$FLAG_FILE" ]]; then
  ok "ksu_access_ok dedupe already applied (flag file present) -- skipping."
  exit 0
fi

COUNT="$(grep -cE '^\s*(static\s+inline\s+|static\s+)?int\s+ksu_access_ok\s*\(' "$COMPAT_C" || true)"
if [[ "$COUNT" -lt 2 ]]; then
  ok "Only $COUNT definition(s) of ksu_access_ok found -- nothing to dedupe."
  touch "$FLAG_FILE"
  exit 0
fi

log "Removing duplicate ksu_access_ok() definition from kernel_compat.c"
cp "$COMPAT_C" "$COMPAT_C.orig-$(date +%s)"
python3 "$(dirname "${BASH_SOURCE[0]}")/dedupe_generic_func.py" "$COMPAT_C" ksu_access_ok

NEW_COUNT="$(grep -cE '^\s*(static\s+inline\s+|static\s+)?int\s+ksu_access_ok\s*\(' "$COMPAT_C" || true)"
if [[ "$NEW_COUNT" -eq 1 ]]; then
  ok "Dedupe successful -- exactly one definition remains."
  touch "$FLAG_FILE"
else
  err "Dedupe ran but $NEW_COUNT definitions remain (expected 1)."
  exit 1
fi
