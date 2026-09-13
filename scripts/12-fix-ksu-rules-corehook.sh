#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../config.env
source lib.sh
require_source_root

KDIR="$SOURCE_ROOT/$KERNEL_TREE_PATH"
RULES_C="$KDIR/drivers/kernelsu/selinux/rules.c"
CORE_HOOK_C="$KDIR/drivers/kernelsu/core_hook.c"

if [[ ! -f "$RULES_C" || ! -f "$CORE_HOOK_C" ]]; then
  warn "drivers/kernelsu/selinux/rules.c or core_hook.c not found -- skipping."
  warn "(expected if INTEGRATE_KSU_SUSFS=false, or KernelSU-Next isn't installed yet.)"
  exit 0
fi

FLAG_FILE="$KDIR/.ksu-rules-corehook-rename-applied"
if [[ -f "$FLAG_FILE" ]]; then
  ok "rules.c/core_hook.c rename fix already applied (flag file present) -- skipping."
  exit 0
fi

# On KernelSU-Next v1.1.1, the SUSFS support patch pinned by SUSFS_PATCH_URL
# fails to apply 3/3 hunks against selinux/rules.c and 2/16 hunks against
# core_hook.c (context has drifted -- see summary-since-v7.md / v8 addendum
# Section 24 for the full diagnosis). The build then compiles but fails at
# final link with undefined symbols: is_manager, ksu_handle_sepolicy,
# is_zygote, try_umount, ksu_apply_kernelsu_rules, getenforce.
#
# This performs the exact leftover renames those failed hunks would have
# made (confirmed by reproducing the setup.sh + patch apply locally against
# a clean v1.1.1 checkout), rather than re-deriving or hand-porting the
# failed hunks against a moving upstream target.
log "Checking for leftover pre-rename KernelSU-Next symbols in rules.c / core_hook.c"
cp "$RULES_C" "$RULES_C.orig-$(date +%s)"
cp "$CORE_HOOK_C" "$CORE_HOOK_C.orig-$(date +%s)"

python3 "$(dirname "${BASH_SOURCE[0]}")/fix_ksu_rules_corehook.py" "$RULES_C" "$CORE_HOOK_C"

# Verify: none of the old, now-undefined names should remain as bare calls.
REMAINING=0
grep -qE '\bvoid[[:space:]]+apply_kernelsu_rules[[:space:]]*\(' "$RULES_C" && REMAINING=1
grep -qE '\bgetenforce[[:space:]]*\([[:space:]]*\)' "$RULES_C" && REMAINING=1
grep -qE '\bint[[:space:]]+handle_sepolicy[[:space:]]*\(' "$RULES_C" && REMAINING=1
grep -qE '\bis_manager[[:space:]]*\([[:space:]]*\)' "$CORE_HOOK_C" && REMAINING=1
grep -qE '\bis_zygote[[:space:]]*\(' "$CORE_HOOK_C" && REMAINING=1
grep -qE '\btry_umount[[:space:]]*\(' "$CORE_HOOK_C" && REMAINING=1

if [[ "$REMAINING" -eq 0 ]]; then
  ok "rules.c / core_hook.c renames verified -- no leftover old-name call sites."
  touch "$FLAG_FILE"
else
  err "Some old-name call sites still remain after the fix -- upstream KernelSU-Next"
  err "source has likely changed shape again. Inspect $RULES_C and $CORE_HOOK_C by hand"
  err "(backups saved alongside as *.orig-<timestamp>) before re-running the build."
  exit 1
fi
