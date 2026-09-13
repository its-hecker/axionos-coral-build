#!/usr/bin/env bash
# 08-fix-kernelrelease.sh
#
# Why this exists:
# KernelSU-Next and susfs4ksu are cloned as their own nested git repos
# inside $KERNEL_TREE_PATH. scripts/setlocalversion walks every nested
# git repo's scm state and concatenates all of them into UTS_RELEASE,
# which the kernel build caps at 64 characters. On coral with KSU-Next +
# SUSFS this reliably overflows it, e.g.:
#
#   4.14.357-openela-ge19fb8e95408-dirty_KernelSU-Next-g4600bfc66490-dirty_susfs4ksu-00043-g77905b5a071e
#
# ...which is 100+ characters and fails the build with:
#   "... exceeds 64 characters"
#
# Fix: patch scripts/setlocalversion so it drops the "-dirty" suffix and
# blanks the final scm-version output, collapsing the whole thing back
# down to just the base kernel version (e.g. "4.14.357-openela").
#
# Safe to re-run — checks before patching so it's idempotent.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../config.env
source lib.sh
require_source_root

KDIR="$SOURCE_ROOT/$KERNEL_TREE_PATH"
[[ -d "$KDIR" ]] || die "Kernel tree not found at $KDIR — run 02-clone-device-trees.sh first."

SETLOCALVERSION="$KDIR/scripts/setlocalversion"
[[ -f "$SETLOCALVERSION" ]] || die "setlocalversion not found at $SETLOCALVERSION"

if ! grep -q -- "printf '%s' -dirty" "$SETLOCALVERSION" && ! grep -q 'echo "\$res"' "$SETLOCALVERSION"; then
  ok "Kernel release string already patched — skipping."
  exit 0
fi

log "Patching scripts/setlocalversion to avoid the 64-char UTS_RELEASE overflow"
cp "$SETLOCALVERSION" "$SETLOCALVERSION.orig-$(date +%s)"

sed -i "s/printf '%s' -dirty/printf '%s' ''/g" "$SETLOCALVERSION"
sed -i 's/echo "\$res"/echo ""/' "$SETLOCALVERSION"
ok "setlocalversion patched (backup saved alongside it)."

UTSRELEASE="$SOURCE_ROOT/out/target/product/$DEVICE_CODENAME/obj/KERNEL_OBJ/include/generated/utsrelease.h"
if [[ -f "$UTSRELEASE" ]]; then
  log "Removing stale cached utsrelease.h so it regenerates with the short string"
  rm -f "$UTSRELEASE"
fi

ok "Kernel release length fix complete."
