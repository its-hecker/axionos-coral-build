#!/usr/bin/env bash
# 09-fix-path-umount.sh
#
# Why this exists:
# KernelSU-Next's core_hook.c (susfs_try_umount / ksu_try_umount) calls
# path_umount(), a VFS function that only exists upstream from Linux 5.9
# onward. msm-4.14 predates it, so the final link fails with:
#
#   ld.lld: error: undefined symbol: path_umount
#   >>> referenced by core_hook.c:759 (drivers/kernelsu/core_hook.c:759)
#   >>>               vmlinux.o:(susfs_try_umount)
#
# This is a known, documented gap for non-GKI kernels -- KernelSU's own
# docs (kernelsu.org/guide/how-to-integrate-for-non-gki.html) ship a
# reference backport of path_umount() + its helper can_umount() for
# exactly this situation. This script applies that backport to
# fs/namespace.c.
#
# Safe to re-run -- checks before patching so it's idempotent.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../config.env
source lib.sh
require_source_root

KDIR="$SOURCE_ROOT/$KERNEL_TREE_PATH"
[[ -d "$KDIR" ]] || die "Kernel tree not found at $KDIR -- run 02-clone-device-trees.sh first."

NAMESPACE_C="$KDIR/fs/namespace.c"
[[ -f "$NAMESPACE_C" ]] || die "fs/namespace.c not found at $NAMESPACE_C"

if grep -q '^int path_umount' "$NAMESPACE_C"; then
  ok "path_umount already backported in fs/namespace.c -- skipping."
  exit 0
fi

log "Backporting path_umount()/can_umount() into fs/namespace.c (KernelSU non-GKI fix)"
cp "$NAMESPACE_C" "$NAMESPACE_C.orig-$(date +%s)"

PATCH_FILE="$(mktemp)"
cat > "$PATCH_FILE" <<'EOF'
--- a/fs/namespace.c
+++ b/fs/namespace.c
@@ -1739,6 +1739,39 @@ static inline bool may_mandlock(void)
 }
 #endif

+static int can_umount(const struct path *path, int flags)
+{
+	struct mount *mnt = real_mount(path->mnt);
+
+	if (flags & ~(MNT_FORCE | MNT_DETACH | MNT_EXPIRE | UMOUNT_NOFOLLOW))
+		return -EINVAL;
+	if (!may_mount())
+		return -EPERM;
+	if (path->dentry != path->mnt->mnt_root)
+		return -EINVAL;
+	if (!check_mnt(mnt))
+		return -EINVAL;
+	if (mnt->mnt.mnt_flags & MNT_LOCKED) /* Check optimistically */
+		return -EINVAL;
+	if (flags & MNT_FORCE && !capable(CAP_SYS_ADMIN))
+		return -EPERM;
+	return 0;
+}
+
+int path_umount(struct path *path, int flags)
+{
+	struct mount *mnt = real_mount(path->mnt);
+	int ret;
+
+	ret = can_umount(path, flags);
+	if (!ret)
+		ret = do_umount(mnt, flags);
+
+	/* we mustn't call path_put() as that would clear mnt_expiry_mark */
+	dput(path->dentry);
+	mntput_no_expire(mnt);
+	return ret;
+}
 /*
  * Now umount can handle mount points as well as block devices.
  * This is important for filesystems which use unnamed block devices.
EOF

cd "$KDIR"
if patch -p1 --dry-run < "$PATCH_FILE" >/dev/null 2>&1; then
  patch -p1 < "$PATCH_FILE"
  ok "path_umount backport applied cleanly."
else
  warn "Reference patch didn't apply cleanly (msm-4.14 has likely drifted around"
  warn "the may_mandlock()/#endif anchor this patch targets)."
  warn "Falling back to appending the functions directly above do_umount()'s"
  warn "SYSCALL_DEFINE for umount, which is more resilient to line drift."

  # Fallback: insert right before the block comment that precedes the
  # umount syscall definitions, so we don't depend on exact line numbers.
  if grep -q '^int path_umount' fs/namespace.c; then
    ok "path_umount already present after all -- nothing more to do."
  else
    python3 - "$NAMESPACE_C" <<'PYEOF'
import re, sys
path = sys.argv[1]
with open(path) as f:
    src = f.read()

backport = '''
static int can_umount(const struct path *path, int flags)
{
	struct mount *mnt = real_mount(path->mnt);

	if (flags & ~(MNT_FORCE | MNT_DETACH | MNT_EXPIRE | UMOUNT_NOFOLLOW))
		return -EINVAL;
	if (!may_mount())
		return -EPERM;
	if (path->dentry != path->mnt->mnt_root)
		return -EINVAL;
	if (!check_mnt(mnt))
		return -EINVAL;
	if (mnt->mnt.mnt_flags & MNT_LOCKED) /* Check optimistically */
		return -EINVAL;
	if (flags & MNT_FORCE && !capable(CAP_SYS_ADMIN))
		return -EPERM;
	return 0;
}

int path_umount(struct path *path, int flags)
{
	struct mount *mnt = real_mount(path->mnt);
	int ret;

	ret = can_umount(path, flags);
	if (!ret)
		ret = do_umount(mnt, flags);

	/* we mustn't call path_put() as that would clear mnt_expiry_mark */
	dput(path->dentry);
	mntput_no_expire(mnt);
	return ret;
}
'''

marker = "Now umount can handle mount points as well as block devices."
idx = src.find(marker)
if idx == -1:
    print("MARKER_NOT_FOUND", file=sys.stderr)
    sys.exit(1)

# back up to the start of the comment block ("/*") preceding the marker
comment_start = src.rfind("/*", 0, idx)
if comment_start == -1:
    print("COMMENT_START_NOT_FOUND", file=sys.stderr)
    sys.exit(1)

new_src = src[:comment_start] + backport.lstrip("\n") + "\n" + src[comment_start:]
with open(path, "w") as f:
    f.write(new_src)
print("PATCHED_VIA_FALLBACK")
PYEOF
    if [[ $? -ne 0 ]]; then
      err "Automatic fallback also failed to find a safe insertion point."
      err "Open $NAMESPACE_C by hand and paste the path_umount()/can_umount()"
      err "backport from https://kernelsu.org/guide/how-to-integrate-for-non-gki.html"
      err "anywhere at file scope (e.g. directly above do_umount's SYSCALL_DEFINE)."
      exit 1
    fi
    ok "path_umount backport applied via fallback insertion."
  fi
fi

rm -f "$PATCH_FILE"

# The KernelSU build sometimes gates on finding path_umount textually in
# fs/namespace.c (some forks check via grep and set -DKSU_HAS_PATH_UMOUNT).
# Nothing else to do here -- the symbol now exists and the linker will find it.

ok "path_umount fix complete."
