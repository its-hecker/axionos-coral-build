#!/usr/bin/env bash
# 10-fix-ksu-unused-label.sh
#
# Why this exists:
# The SUSFS support patch for KernelSU-Next adds a ksu_try_umount()
# function with a goto target, out_ksu_try_umount. On KernelSU-Next
# v1.1.1, the syscall-hook version was reverted from v1.5 back to v1.4
# (CPU-compat hotfix for older ARMv8.0-8.2 cores on Kprobes). That revert
# removed the only goto that ever jumped to this label, but the label
# itself was left in place -- so it's now genuinely unreferenced.
#
# AOSP kernel builds treat -Wunused-label as a fatal error, so this alone
# fails the whole build:
#
#   drivers/kernelsu/core_hook.c:1004:1: error: unused label
#   'out_ksu_try_umount' [-Werror,-Wunused-label]
#
# Fix: annotate the label with __attribute__((unused)), the documented
# GCC/Clang way to mark a label as intentionally possibly-unreferenced.
# This does not disable -Werror or -Wunused-label globally -- only this
# one label is annotated, so any other genuinely-unused label elsewhere
# in the kernel is still caught.
#
# core_hook.c is reinstalled fresh every time KernelSU-Next is (re)cloned
# by 04-ksu-susfs.sh (e.g. on a KSU_VERSION bump), so this script
# re-checks and reapplies on every run rather than relying on a one-time
# flag file the way 09-fix-path-umount.sh does for fs/namespace.c.
#
# Safe to re-run -- checks before patching so it's idempotent, and is a
# no-op if a future KernelSU-Next/SUSFS combination doesn't have this
# exact label at all.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../config.env
source lib.sh
require_source_root

KDIR="$SOURCE_ROOT/$KERNEL_TREE_PATH"
CORE_HOOK="$KDIR/drivers/kernelsu/core_hook.c"

if [[ ! -f "$CORE_HOOK" ]]; then
  warn "drivers/kernelsu/core_hook.c not found -- skipping unused-label fix"
  warn "(expected if INTEGRATE_KSU_SUSFS=false, or KSU-Next isn't installed yet)."
  exit 0
fi

if grep -q 'out_ksu_try_umount: __attribute__((unused));' "$CORE_HOOK"; then
  ok "Unused-label fix already applied to core_hook.c -- skipping."
  exit 0
fi

if ! grep -qE '^out_ksu_try_umount:[[:space:]]*$' "$CORE_HOOK"; then
  ok "out_ksu_try_umount label not present (or not bare) in this KernelSU-Next"
  ok "version -- nothing to do."
  exit 0
fi

LABEL_USES="$(grep -c 'goto out_ksu_try_umount' "$CORE_HOOK" || true)"
if [[ "$LABEL_USES" -ge 1 ]]; then
  ok "out_ksu_try_umount is actually referenced by a goto in this version"
  ok "($LABEL_USES use(s) found) -- leaving it alone."
  exit 0
fi

log "Annotating unused label 'out_ksu_try_umount' in core_hook.c"
cp "$CORE_HOOK" "$CORE_HOOK.orig-$(date +%s)"
sed -i -E 's/^out_ksu_try_umount:[[:space:]]*$/out_ksu_try_umount: __attribute__((unused));/' "$CORE_HOOK"

if grep -q 'out_ksu_try_umount: __attribute__((unused));' "$CORE_HOOK"; then
  ok "Unused-label fix applied cleanly."
else
  err "sed ran but the expected annotated line wasn't found afterward."
  err "Open $CORE_HOOK by hand around 'out_ksu_try_umount:' and add"
  err "__attribute__((unused)) right after the colon."
  exit 1
fi
