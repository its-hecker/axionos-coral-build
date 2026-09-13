#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../config.env
source lib.sh
require_source_root

if [[ "${INTEGRATE_KSU_SUSFS,,}" != "true" ]]; then
  warn "INTEGRATE_KSU_SUSFS is set to \"$INTEGRATE_KSU_SUSFS\" in config.env — skipping"
  warn "KernelSU-Next + SUSFS integration. This will be a stock, non-rooted kernel build."
  exit 0
fi

KDIR="$SOURCE_ROOT/$KERNEL_TREE_PATH"
[[ -d "$KDIR" ]] || die "Kernel tree not found at $KDIR — run 02-clone-device-trees.sh first."
cd "$KDIR"

INSTALLED_VERSION=""
if [[ -d KernelSU-Next/.git ]]; then
  INSTALLED_VERSION="$(git -C KernelSU-Next describe --tags 2>/dev/null || true)"
fi

if [[ -d KernelSU-Next && "$INSTALLED_VERSION" == "$KSU_VERSION" ]]; then
  ok "KernelSU-Next $KSU_VERSION already present in kernel tree — skipping setup."
else
  if [[ -d KernelSU-Next ]]; then
    warn "KernelSU-Next present but at ${INSTALLED_VERSION:-unknown}, config.env wants $KSU_VERSION."
    warn "Removing old checkout so the version bump actually takes effect."
    rm -rf KernelSU-Next
  fi
  log "Installing KernelSU-Next $KSU_VERSION"
  curl -LSs "$KSU_SETUP_URL" | bash -s "$KSU_VERSION"
fi

cd KernelSU-Next

if [[ -f .susfs-patch-applied ]]; then
  ok "SUSFS-for-KernelSU-Next patch already applied — skipping."
else
  log "Pulling SUSFS support patch for KernelSU-Next"
  curl -o 0001-Kernel-Implement-SUSFS-v1.5.3.patch "$SUSFS_PATCH_URL"

  # NOTE: on some KernelSU-Next versions (e.g. v1.1.1) this patch is known
  # to apply cleanly for most hunks but reject a handful whose surrounding
  # context has drifted upstream (see scripts/12-fix-ksu-rules-corehook.sh
  # for the full diagnosis). A `--dry-run` gate that demands 100% clean
  # application would refuse to apply ANY of it in that case -- including
  # the hunks that DO still apply cleanly -- and scripts 10/11/12 would
  # never get a chance to patch up the rest. So: always attempt the real
  # patch, let whatever hunks succeed land, and don't hard-fail here. If
  # something is applied badly enough that the fix scripts can't reconcile
  # it, script 12's own verification step will catch it and fail loudly.
  set +e
  patch -p1 < 0001-Kernel-Implement-SUSFS-v1.5.3.patch
  PATCH_EXIT=$?
  set -e

  if [[ "$PATCH_EXIT" -eq 0 ]]; then
    ok "Patch applied cleanly."
  else
    warn "Patch did not apply 100% cleanly -- some hunks were rejected"
    warn "(see kernel/*.rej and kernel/selinux/*.rej files under KernelSU-Next"
    warn "for exactly which ones, if you want to inspect them)."
    warn "Continuing: scripts 10, 11, and 12 (run right after this step)"
    warn "patch up the known leftover call sites for KSU_VERSION=$KSU_VERSION."
  fi
  touch .susfs-patch-applied
fi

cd "$KDIR"

if [[ -d susfs4ksu ]]; then
  ok "susfs4ksu already cloned — skipping."
else
  log "Cloning susfs4ksu ($SUSFS_KERNEL_BRANCH)"
  git clone "$SUSFS_REPO_URL" -b "$SUSFS_KERNEL_BRANCH" susfs4ksu
fi

if [[ -f .susfs-kernel-patch-applied ]]; then
  ok "Kernel-level SUSFS patch already applied — skipping."
else
  log "Copying SUSFS fs/ and include/linux/ files into the kernel tree"
  cp -v susfs4ksu/kernel_patches/fs/* fs/
  cp -v susfs4ksu/kernel_patches/include/linux/* include/linux/

  log "Applying 50_add_susfs_in_kernel-4.14.patch"
  cp -v susfs4ksu/kernel_patches/50_add_susfs_in_kernel-4.14.patch .
  if patch -p1 --dry-run < 50_add_susfs_in_kernel-4.14.patch >/dev/null 2>&1; then
    patch -p1 < 50_add_susfs_in_kernel-4.14.patch
    touch .susfs-kernel-patch-applied
    ok "Kernel patch applied cleanly."
  else
    err "50_add_susfs_in_kernel-4.14.patch does not apply cleanly."
    err "The msm-4.14 tree has likely drifted from what this patch expects."
    err "Run 'patch -p1 < 50_add_susfs_in_kernel-4.14.patch' manually, inspect"
    err "any .rej files, and resolve the conflicting hunks by hand."
    exit 1
  fi
fi

log "Checking defconfig for required KernelSU-Next options..."
DEFCONFIG_DIR="arch/arm64/configs"
if grep -rL "CONFIG_KPROBES=y" "$DEFCONFIG_DIR"/*coral* 2>/dev/null | grep -q .; then
  warn "CONFIG_KPROBES=y not found in one or more coral defconfigs — add it manually,"
  warn "KernelSU-Next needs this for its kernel hooks."
fi
if grep -rL "CONFIG_MODULES=y" "$DEFCONFIG_DIR"/*coral* 2>/dev/null | grep -q .; then
  warn "CONFIG_MODULES=y not found in one or more coral defconfigs — add it manually."
fi

ok "KernelSU-Next + SUSFS integration complete."

# KernelSU-Next + susfs4ksu are nested git repos inside the kernel tree,
# which pushes UTS_RELEASE past the kernel's 64-char limit. Fix it now,
# right after integration, so a clean build never hits the overflow.
"$SCRIPT_DIR/08-fix-kernelrelease.sh"

# msm-4.14 predates path_umount() (added upstream in Linux 5.9), which
# KernelSU-Next's core_hook.c calls directly for its umount-hiding logic.
# Without this backport the final kernel link fails with
# "undefined symbol: path_umount". Fix it now, right after integration,
# so a clean build never hits it.
"$SCRIPT_DIR/09-fix-path-umount.sh"

# The SUSFS patch's ksu_try_umount() defines a goto target that some
# KernelSU-Next versions (e.g. v1.1.1, after its syscall-hook-version
# revert) never actually jump to, which AOSP's -Werror turns into a
# build-breaking "unused label" error. Fix it now, right after
# integration, so a clean build never hits it.
"$SCRIPT_DIR/10-fix-ksu-unused-label.sh"

# The SUSFS support patch's copy of ksu_access_ok() in kernel_compat.c
# collides with v1.1.1's own native (non-static) definition of the same
# function, which is a build-breaking redefinition error. Fix it now,
# right after integration, so a clean build never hits it.
"$SCRIPT_DIR/11-fix-ksu-access-ok.sh"

# On v1.1.1, the pinned SUSFS support patch fails to apply 3/3 hunks
# against selinux/rules.c and 2/16 hunks against core_hook.c (upstream
# context has drifted since the patch was written). The build compiles
# but fails at final link with undefined symbols (is_manager,
# ksu_handle_sepolicy, is_zygote, try_umount, ksu_apply_kernelsu_rules,
# getenforce). Fix it now, right after integration, so a clean build
# never hits it.
"$SCRIPT_DIR/12-fix-ksu-rules-corehook.sh"
