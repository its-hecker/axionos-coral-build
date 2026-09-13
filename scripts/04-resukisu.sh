#!/usr/bin/env bash
# 04-resukisu.sh
#
# Replaces 04-ksu-susfs.sh. Integrates ReSukiSU (https://github.com/ReSukiSU/ReSukiSU)
# instead of KernelSU-Next, and deliberately does NOT integrate SUSFS at all --
# see the KSU-1.1.1-migration doc for why we're moving off that combination
# (clean-flashed wifi broke on the KSU-Next v1.1.1 + hand-patched SUSFS build;
# root cause not conclusively isolated before deciding to switch).
#
# coral's kernel (msm-4.14) is well below ReSukiSU's GKI 2.0 floor for its
# default Tracepoint hook, so this uses Manual Hook mode
# (https://resukisu.org/guide/build.html), with the 4 required call sites
# inserted by scripts/patch_resukisu_manual_hooks.py.
#
# Safe to re-run -- checks before each destructive step so it's idempotent.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../config.env
source lib.sh
require_source_root

if [[ "${INTEGRATE_KSU,,}" != "true" ]]; then
  warn "INTEGRATE_KSU is set to \"$INTEGRATE_KSU\" in config.env — skipping"
  warn "ReSukiSU integration. This will be a stock, non-rooted kernel build."
  exit 0
fi

KDIR="$SOURCE_ROOT/$KERNEL_TREE_PATH"
[[ -d "$KDIR" ]] || die "Kernel tree not found at $KDIR — run 02-clone-device-trees.sh first."
cd "$KDIR"

# --- Safety guard: refuse to layer ReSukiSU on top of a tree that still has
# old KSU-Next+SUSFS modifications in it. SUSFS's own kernel-side hook patch
# (50_add_susfs_in_kernel-4.14.patch, applied by the old 04-ksu-susfs.sh)
# is a real diff against fs/stat.c, fs/open.c, kernel/reboot.c and friends --
# the exact files this script's hook patcher also needs to touch. Layering
# on top risks either silently-wrong duplicate hooks or the patcher's
# anchors simply not matching anymore. If this fires, the right move is a
# fresh kernel tree checkout (rm -rf this KDIR and re-run
# 02-clone-device-trees.sh), not forcing through it.
if [[ -d KernelSU-Next ]] || grep -rq "susfs" fs/stat.c fs/open.c kernel/reboot.c 2>/dev/null; then
  die "This kernel tree still has old KernelSU-Next / SUSFS modifications in
  it (found a KernelSU-Next/ dir and/or 'susfs' references in fs/stat.c,
  fs/open.c, or kernel/reboot.c). Layering ReSukiSU's manual hooks on top of
  that is not safe -- re-clone a clean kernel tree first:
    rm -rf \"$KDIR\"
    ./build.sh trees
  then re-run this step."
fi

# --- Install ReSukiSU ---
INSTALLED_COMMIT=""
if [[ -d KernelSU/.git ]]; then
  INSTALLED_COMMIT="$(git -C KernelSU rev-parse HEAD 2>/dev/null || true)"
fi

if [[ -d KernelSU && -n "$INSTALLED_COMMIT" && -z "${RESUKISU_VERSION}" ]]; then
  ok "ReSukiSU already present in kernel tree (unpinned/main) — leaving as-is."
  ok "Delete kernel/google/msm-4.14/KernelSU and re-run to pull latest main."
elif [[ -d KernelSU ]] && [[ -n "${RESUKISU_VERSION}" ]] \
     && [[ "$(git -C KernelSU describe --tags --exact-match 2>/dev/null || true)" == "$RESUKISU_VERSION" ]]; then
  ok "ReSukiSU $RESUKISU_VERSION already present — skipping setup."
else
  log "Installing ReSukiSU ${RESUKISU_VERSION:-(latest main)}"
  curl -LSs "$RESUKISU_SETUP_URL" | bash -s ${RESUKISU_VERSION:+"$RESUKISU_VERSION"}
fi

# --- Defconfig: enable CONFIG_KSU + Manual Hook mode ---
# coral's LineageOS device tree points TARGET_KERNEL_CONFIG at
# floral_defconfig (shared across several Pixel devices in this tree, not
# just floral -- that's normal for LineageOS's config layout, not a bug).
DEFCONFIG="arch/arm64/configs/floral_defconfig"
[[ -f "$DEFCONFIG" ]] || die "Expected defconfig not found at $DEFCONFIG. If \
coral's device tree targets a different file, update DEFCONFIG in this \
script to match."

log "Checking $DEFCONFIG for required ReSukiSU options..."

set_defconfig_opt() {
  local opt="$1" val="$2"
  if grep -q "^${opt}=${val}\$" "$DEFCONFIG"; then
    ok "$opt=$val already set."
  elif grep -q "^${opt}=" "$DEFCONFIG"; then
    sed -i "s/^${opt}=.*/${opt}=${val}/" "$DEFCONFIG"
    ok "$opt changed to $val."
  elif grep -q "^# ${opt} is not set\$" "$DEFCONFIG"; then
    sed -i "s/^# ${opt} is not set/${opt}=${val}/" "$DEFCONFIG"
    ok "$opt enabled (was explicitly disabled)."
  else
    echo "${opt}=${val}" >> "$DEFCONFIG"
    ok "$opt=$val appended."
  fi
}

set_defconfig_opt "CONFIG_KSU" "y"
set_defconfig_opt "CONFIG_KSU_MANUAL_HOOK" "y"
# Kernel is well under 6.8, so these three "auto hook" options cover
# input/setuid/sys_read without needing to hand-patch drivers/input/input.c
# or kernel/sys.c or fs/read_write.c -- per
# https://resukisu.org/guide/manual-integrate.html
set_defconfig_opt "CONFIG_KSU_MANUAL_HOOK_AUTO_INPUT_HOOK" "y"
set_defconfig_opt "CONFIG_KSU_MANUAL_HOOK_AUTO_SETUID_HOOK" "y"
set_defconfig_opt "CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK" "y"

# Deliberately NOT setting CONFIG_KSU_SUSFS -- that's the whole point of
# this migration. If it's present and =y from an old edit, turn it back off.
if grep -q "^CONFIG_KSU_SUSFS=y\$" "$DEFCONFIG"; then
  warn "CONFIG_KSU_SUSFS=y found in $DEFCONFIG from a previous run -- \
disabling it, this build intentionally does not use SUSFS."
  sed -i "s/^CONFIG_KSU_SUSFS=y/# CONFIG_KSU_SUSFS is not set/" "$DEFCONFIG"
fi

if grep -q "^CONFIG_KALLSYMS_ALL=y\$" "$DEFCONFIG"; then
  ok "CONFIG_KALLSYMS_ALL=y already set -- ReSukiSU's static-symbol-export \
patches (write_op, sel_handle_status_ops, etc. in security/selinux/) are \
NOT needed. See https://resukisu.org/guide/manual-integrate.html."
else
  warn "CONFIG_KALLSYMS_ALL is not set in $DEFCONFIG. Either enable it \
(simplest) or you'll need to hand-apply the SELinux static-symbol-export \
patches from https://resukisu.org/guide/manual-integrate.html yourself -- \
this script does not attempt those, they're fragile hand-edits to \
security/selinux/*.c that are easy to get subtly wrong."
fi

# --- Apply the 4 required Manual Hook call sites ---
log "Applying ReSukiSU Manual Hook call sites (stat, execve, faccessat, sys_reboot)"
python3 "$(dirname "${BASH_SOURCE[0]}")/patch_resukisu_manual_hooks.py" \
  fs/stat.c fs/exec.c fs/open.c kernel/reboot.c

log "Verifying hooks landed..."
for pair in "fs/stat.c:ksu_handle_stat" "fs/exec.c:ksu_handle_execveat" \
            "fs/open.c:ksu_handle_faccessat" "kernel/reboot.c:ksu_handle_sys_reboot"; do
  f="${pair%%:*}"; sym="${pair##*:}"
  grep -q "$sym" "$f" || die "$sym not found in $f after patching -- something went wrong, check $f.orig-* backups."
done
ok "All 4 required Manual Hook call sites verified present."

ok "ReSukiSU integration complete (Manual Hook mode, no SUSFS)."

# NOTE: intentionally NOT auto-calling 08-fix-kernelrelease.sh or
# 09-fix-path-umount.sh here (unlike the old 04-ksu-susfs.sh). Both existed
# specifically for the KSU-Next+SUSFS combination:
#   - 08 worked around UTS_RELEASE overflowing 64 chars, driven by
#     KernelSU-Next's AND susfs4ksu's nested-repo scm strings concatenating.
#     A single ReSukiSU checkout is much less likely to hit that on its own,
#     but if 06-build.sh fails with "exceeds 64 characters", run it manually:
#       ./build.sh kernelrelease-fix
#   - 09 backported path_umount() specifically for SUSFS's umount-hiding
#     call in core_hook.c, which doesn't exist in this build at all now.
#     If a future ReSukiSU version calls path_umount() directly for its own
#     (non-SUSFS) umount handling on a pre-5.9 kernel, you'll see the same
#     "undefined symbol: path_umount" link error the old doc described --
#     the fix script is unchanged and still works, just isn't auto-run:
#       ./build.sh path-umount-fix
