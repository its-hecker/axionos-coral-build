#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../config.env
source lib.sh
require_source_root

KDIR="$SOURCE_ROOT/$KERNEL_TREE_PATH"
[[ -d "$KDIR" ]] || die "Kernel tree not found at $KDIR — run 02-clone-device-trees.sh first."
cd "$KDIR"

if [[ -d KernelSU-Next ]]; then
  ok "KernelSU-Next already present in kernel tree — skipping setup."
else
  log "Installing KernelSU-Next $KSU_VERSION"
  curl -LSs "$KSU_SETUP_URL" | bash -s "$KSU_VERSION"
fi

cd KernelSU-Next

if [[ -f .susfs-patch-applied ]]; then
  ok "SUSFS-for-KernelSU-Next patch already applied — skipping."
else
  log "Pulling SUSFS support patch for KernelSU-Next"
  curl -o 0001-Kernel-Implement-SUSFS-v1.5.3.patch "$SUSFS_PATCH_URL"
  if patch -p1 --dry-run < 0001-Kernel-Implement-SUSFS-v1.5.3.patch >/dev/null 2>&1; then
    patch -p1 < 0001-Kernel-Implement-SUSFS-v1.5.3.patch
    touch .susfs-patch-applied
    ok "Patch applied cleanly."
  else
    err "Patch does not apply cleanly against this KernelSU-Next checkout."
    err "This usually means the KSU_VERSION in config.env has drifted from what"
    err "the patch expects. Try 'patch -p1 < 0001-...patch' manually and resolve"
    err "any .rej files by hand, or pin an older KSU_VERSION."
    exit 1
  fi
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
