#!/usr/bin/env python3
"""
Applies ReSukiSU's required Manual Hook call sites to a msm-4.14 kernel tree.

Why manual hooks at all: ReSukiSU's default hook mode (Tracepoint Syscall
Redirect) only supports GKI 2.0 kernels (5.10+). coral's kernel is
msm-4.14, so CONFIG_KSU_MANUAL_HOOK is required instead, per
https://resukisu.org/guide/build.html -- which means the 4 "Required" call
sites from https://resukisu.org/guide/manual-integrate.html have to be
inserted by hand: stat, execve, faccessat, sys_reboot. (input/setuid/sys_read
are NOT hooked here -- they're only required on kernel 6.8+, and coral is
4.14, so the CONFIG_KSU_MANUAL_HOOK_AUTO_* Kconfig options cover them
instead; see 04-resukisu.sh.)

Every insertion below was checked against a clean, unmodified clone of
https://github.com/LineageOS/android_kernel_google_msm-4.14 (the exact repo
config.env points at) to confirm the anchor text matches this kernel's real
layout, not just the guide's generic upstream diff -- same due diligence as
scripts/fix_ksu_rules_corehook.py used for the old KSU-Next+SUSFS migration.
Specifically, on this tree:
  - fs/exec.c's do_execveat_common(int fd, struct filename *filename, ...)
    is the single choke point for do_execve/do_execveat/compat_do_execve/
    compat_do_execveat, matching the guide's "3.14+" execve hook exactly.
  - fs/open.c's faccessat is NOT split into a separate do_faccessat() --
    the hook goes directly inside SYSCALL_DEFINE3(faccessat, ...), matching
    the guide's "4.19-" variant.
  - kernel/reboot.c (not kernel/sys.c) holds SYSCALL_DEFINE4(reboot, ...),
    matching the guide's "3.11+" variant.
  - fs/stat.c's newfstatat/newfstat/fstat64/fstatat64 layout matches the
    guide's generic diff verbatim.

Idempotent: every insertion is guarded by checking whether its ksu_handle_*
call is already present. Safe to re-run.
"""
import re
import sys
import shutil
import time


def backup(path):
    bak = f"{path}.orig-{int(time.time())}"
    shutil.copy2(path, bak)
    return bak


def patch_stat_c(path):
    with open(path) as f:
        src = f.read()
    if "ksu_handle_stat" in src:
        return []
    original = src
    changes = []

    # extern decls, anchored right before newfstatat (matches this tree's
    # real line ~356, not just the guide's generic upstream line number).
    anchor = (
        "#if !defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_SYS_NEWFSTATAT)\n"
        "SYSCALL_DEFINE4(newfstatat, int, dfd, const char __user *, filename,\n"
        "\t\tstruct stat __user *, statbuf, int, flag)\n"
        "{\n"
        "\tstruct kstat stat;\n"
        "\tint error;\n"
        "\n"
        "\terror = vfs_fstatat(dfd, filename, &stat, flag);\n"
    )
    if anchor not in src:
        print("ERROR: fs/stat.c newfstatat anchor not found -- tree has "
              "drifted from the clean checkout this was verified against.",
              file=sys.stderr)
        sys.exit(1)

    extern_block = (
        "#ifdef CONFIG_KSU_MANUAL_HOOK\n"
        "__attribute__((hot))\n"
        "extern int ksu_handle_stat(int *dfd, const char __user **filename_user,\n"
        "\t\t\t\tint *flags);\n"
        "\n"
        "extern void ksu_handle_newfstat_ret(unsigned int *fd, struct stat __user **statbuf_ptr);\n"
        "#if defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_COMPAT_STAT64)\n"
        "extern void ksu_handle_fstat64_ret(unsigned long *fd, struct stat64 __user **statbuf_ptr);\n"
        "#endif\n"
        "#endif\n"
        "\n"
    )
    new_newfstatat = (
        "#if !defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_SYS_NEWFSTATAT)\n"
        "SYSCALL_DEFINE4(newfstatat, int, dfd, const char __user *, filename,\n"
        "\t\tstruct stat __user *, statbuf, int, flag)\n"
        "{\n"
        "\tstruct kstat stat;\n"
        "\tint error;\n"
        "\n"
        "#ifdef CONFIG_KSU_MANUAL_HOOK\n"
        "\tksu_handle_stat(&dfd, &filename, &flag);\n"
        "#endif\n"
        "\terror = vfs_fstatat(dfd, filename, &stat, flag);\n"
    )
    src = src.replace(anchor, extern_block + new_newfstatat, 1)
    changes.append("inserted stat-hook extern decls + newfstatat call")

    # newfstat return hook
    newfstat_anchor = (
        "SYSCALL_DEFINE2(newfstat, unsigned int, fd, struct stat __user *, statbuf)\n"
        "{\n"
        "\tstruct kstat stat;\n"
        "\tint error = vfs_fstat(fd, &stat);\n"
        "\n"
        "\tif (!error)\n"
        "\t\terror = cp_new_stat(&stat, statbuf);\n"
        "\n"
        "\treturn error;\n"
        "}\n"
    )
    if newfstat_anchor not in src:
        print("ERROR: fs/stat.c newfstat anchor not found.", file=sys.stderr)
        sys.exit(1)
    newfstat_new = (
        "SYSCALL_DEFINE2(newfstat, unsigned int, fd, struct stat __user *, statbuf)\n"
        "{\n"
        "\tstruct kstat stat;\n"
        "\tint error = vfs_fstat(fd, &stat);\n"
        "\n"
        "\tif (!error)\n"
        "\t\terror = cp_new_stat(&stat, statbuf);\n"
        "\n"
        "#ifdef CONFIG_KSU_MANUAL_HOOK\n"
        "\tksu_handle_newfstat_ret(&fd, &statbuf);\n"
        "#endif\n"
        "\treturn error;\n"
        "}\n"
    )
    src = src.replace(newfstat_anchor, newfstat_new, 1)
    changes.append("inserted newfstat return hook")

    # fstatat64 call hook (32-bit compat path -- only present when
    # __ARCH_WANT_STAT64 / __ARCH_WANT_COMPAT_STAT64 is defined, which is
    # the normal case for an arm64 build with CONFIG_COMPAT for 32-bit apps)
    fstatat64_anchor = (
        "SYSCALL_DEFINE4(fstatat64, int, dfd, const char __user *, filename,\n"
        "\t\tstruct stat64 __user *, statbuf, int, flag)\n"
        "{\n"
        "\tstruct kstat stat;\n"
        "\tint error;\n"
        "\n"
        "\terror = vfs_fstatat(dfd, filename, &stat, flag);\n"
    )
    if fstatat64_anchor in src:
        fstatat64_new = (
            "SYSCALL_DEFINE4(fstatat64, int, dfd, const char __user *, filename,\n"
            "\t\tstruct stat64 __user *, statbuf, int, flag)\n"
            "{\n"
            "\tstruct kstat stat;\n"
            "\tint error;\n"
            "\n"
            "#ifdef CONFIG_KSU_MANUAL_HOOK // 32-bit su\n"
            "\tksu_handle_stat(&dfd, &filename, &flag);\n"
            "#endif\n"
            "\terror = vfs_fstatat(dfd, filename, &stat, flag);\n"
        )
        src = src.replace(fstatat64_anchor, fstatat64_new, 1)
        changes.append("inserted fstatat64 call hook (32-bit)")

        fstat64_anchor = (
            "SYSCALL_DEFINE2(fstat64, unsigned long, fd, struct stat64 __user *, statbuf)\n"
            "{\n"
            "\tstruct kstat stat;\n"
            "\tint error = vfs_fstat(fd, &stat);\n"
            "\n"
            "\tif (!error)\n"
            "\t\terror = cp_new_stat64(&stat, statbuf);\n"
            "\n"
            "\treturn error;\n"
            "}\n"
        )
        if fstat64_anchor in src:
            fstat64_new = (
                "SYSCALL_DEFINE2(fstat64, unsigned long, fd, struct stat64 __user *, statbuf)\n"
                "{\n"
                "\tstruct kstat stat;\n"
                "\tint error = vfs_fstat(fd, &stat);\n"
                "\n"
                "\tif (!error)\n"
                "\t\terror = cp_new_stat64(&stat, statbuf);\n"
                "\n"
                "#ifdef CONFIG_KSU_MANUAL_HOOK // for 32-bit\n"
                "\tksu_handle_fstat64_ret(&fd, &statbuf);\n"
                "#endif\n"
                "\treturn error;\n"
                "}\n"
            )
            src = src.replace(fstat64_anchor, fstat64_new, 1)
            changes.append("inserted fstat64 return hook (32-bit)")
    else:
        print("NOTE: __ARCH_WANT_STAT64 block not found as expected -- "
              "32-bit compat stat hooks skipped. If this build supports "
              "32-bit apps, that path is unprotected; check manually.",
              file=sys.stderr)

    with open(path, "w") as f:
        f.write(src)
    return changes


def patch_exec_c(path):
    with open(path) as f:
        src = f.read()
    if "ksu_handle_execveat" in src:
        return []

    anchor = (
        "static int do_execveat_common(int fd, struct filename *filename,\n"
        "\t\t\t      struct user_arg_ptr argv,\n"
        "\t\t\t      struct user_arg_ptr envp,\n"
        "\t\t\t      int flags)\n"
        "{\n"
        "\treturn __do_execve_file(fd, filename, argv, envp, flags, NULL);\n"
        "}\n"
    )
    if anchor not in src:
        print("ERROR: fs/exec.c do_execveat_common anchor not found.",
              file=sys.stderr)
        sys.exit(1)

    new = (
        "#ifdef CONFIG_KSU_MANUAL_HOOK\n"
        "__attribute__((hot))\n"
        "extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,\n"
        "\t\t\t\tvoid *argv, void *envp, int *flags);\n"
        "#endif\n"
        "\n"
        "static int do_execveat_common(int fd, struct filename *filename,\n"
        "\t\t\t      struct user_arg_ptr argv,\n"
        "\t\t\t      struct user_arg_ptr envp,\n"
        "\t\t\t      int flags)\n"
        "{\n"
        "#ifdef CONFIG_KSU_MANUAL_HOOK\n"
        "\tksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);\n"
        "#endif\n"
        "\n"
        "\treturn __do_execve_file(fd, filename, argv, envp, flags, NULL);\n"
        "}\n"
    )
    src = src.replace(anchor, new, 1)
    with open(path, "w") as f:
        f.write(src)
    return ["hooked do_execveat_common (covers do_execve/do_execveat/"
            "compat_do_execve/compat_do_execveat)"]


def patch_open_c(path):
    with open(path) as f:
        src = f.read()
    if "ksu_handle_faccessat" in src:
        return []

    anchor = (
        "SYSCALL_DEFINE4(fallocate, int, fd, int, mode, loff_t, offset, loff_t, len)\n"
        "{\n"
        "\tstruct fd f = fdget(fd);\n"
        "\tint error = -EBADF;\n"
        "\n"
        "\tif (f.file) {\n"
        "\t\terror = vfs_fallocate(f.file, mode, offset, len);\n"
        "\t\tfdput(f);\n"
        "\t}\n"
        "\treturn error;\n"
        "}\n"
        "\n"
        "/*\n"
        " * access() needs to use the real uid/gid, not the effective uid/gid.\n"
        " * We do this by temporarily clearing all FS-related capabilities and\n"
        " * switching the fsuid/fsgid around to the real ones.\n"
        " */\n"
        "SYSCALL_DEFINE3(faccessat, int, dfd, const char __user *, filename, int, mode)\n"
        "{\n"
        "\tconst struct cred *old_cred;\n"
        "\tstruct cred *override_cred;\n"
        "\tstruct path path;\n"
        "\tstruct inode *inode;\n"
        "\tstruct vfsmount *mnt;\n"
        "\tint res;\n"
        "\tunsigned int lookup_flags = LOOKUP_FOLLOW;\n"
        "\n"
        "\tif (mode & ~S_IRWXO)\t/* where's F_OK, X_OK, W_OK, R_OK? */\n"
        "\t\treturn -EINVAL;\n"
    )
    if anchor not in src:
        print("ERROR: fs/open.c faccessat anchor not found.", file=sys.stderr)
        sys.exit(1)

    new = anchor.replace(
        "SYSCALL_DEFINE4(fallocate, int, fd, int, mode, loff_t, offset, loff_t, len)\n"
        "{",
        "#ifdef CONFIG_KSU_MANUAL_HOOK\n"
        "__attribute__((hot))\n"
        "extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,\n"
        "\t\t\t\tint *mode, int *flags);\n"
        "#endif\n"
        "\n"
        "SYSCALL_DEFINE4(fallocate, int, fd, int, mode, loff_t, offset, loff_t, len)\n"
        "{",
        1,
    ).replace(
        "unsigned int lookup_flags = LOOKUP_FOLLOW;\n"
        "\n"
        "\tif (mode & ~S_IRWXO)",
        "unsigned int lookup_flags = LOOKUP_FOLLOW;\n"
        "\n"
        "#ifdef CONFIG_KSU_MANUAL_HOOK\n"
        "\tksu_handle_faccessat(&dfd, &filename, &mode, NULL);\n"
        "#endif\n"
        "\n"
        "\tif (mode & ~S_IRWXO)",
        1,
    )
    src = src.replace(anchor, new, 1)
    with open(path, "w") as f:
        f.write(src)
    return ["hooked faccessat"]


def patch_reboot_c(path):
    with open(path) as f:
        src = f.read()
    if "ksu_handle_sys_reboot" in src:
        return []

    anchor = (
        "SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,\n"
        "\t\tvoid __user *, arg)\n"
        "{\n"
        "\tstruct pid_namespace *pid_ns = task_active_pid_ns(current);\n"
        "\tchar buffer[256];\n"
        "\tint ret = 0;\n"
        "\n"
        "\t/* We only trust the superuser with rebooting the system. */\n"
        "\tif (!ns_capable(pid_ns->user_ns, CAP_SYS_BOOT))\n"
    )
    if anchor not in src:
        print("ERROR: kernel/reboot.c SYSCALL_DEFINE4(reboot,...) anchor not found.",
              file=sys.stderr)
        sys.exit(1)

    new = (
        "#ifdef CONFIG_KSU_MANUAL_HOOK\n"
        "extern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg);\n"
        "#endif\n"
        "\n"
        "SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,\n"
        "\t\tvoid __user *, arg)\n"
        "{\n"
        "\tstruct pid_namespace *pid_ns = task_active_pid_ns(current);\n"
        "\tchar buffer[256];\n"
        "\tint ret = 0;\n"
        "\n"
        "#ifdef CONFIG_KSU_MANUAL_HOOK\n"
        "\tksu_handle_sys_reboot(magic1, magic2, cmd, &arg);\n"
        "#endif\n"
        "\t/* We only trust the superuser with rebooting the system. */\n"
        "\tif (!ns_capable(pid_ns->user_ns, CAP_SYS_BOOT))\n"
    )
    src = src.replace(anchor, new, 1)
    with open(path, "w") as f:
        f.write(src)
    return ["hooked SYSCALL_DEFINE4(reboot,...)"]


def main():
    if len(sys.argv) != 5:
        print(f"Usage: {sys.argv[0]} <fs/stat.c> <fs/exec.c> <fs/open.c> "
              "<kernel/reboot.c>", file=sys.stderr)
        sys.exit(1)

    stat_c, exec_c, open_c, reboot_c = sys.argv[1:5]
    already_hooked_marker = {
        "patch_stat_c": "ksu_handle_stat",
        "patch_exec_c": "ksu_handle_execveat",
        "patch_open_c": "ksu_handle_faccessat",
        "patch_reboot_c": "ksu_handle_sys_reboot",
    }
    all_changes = []

    for label, path, fn in (
        ("fs/stat.c", stat_c, patch_stat_c),
        ("fs/exec.c", exec_c, patch_exec_c),
        ("fs/open.c", open_c, patch_open_c),
        ("kernel/reboot.c", reboot_c, patch_reboot_c),
    ):
        with open(path) as f:
            already_done = already_hooked_marker[fn.__name__] in f.read()

        if already_done:
            print(f"[{label}] already hooked -- skipping.")
            continue

        backup(path)
        changes = fn(path)
        for c in changes:
            print(f"[{label}] {c}")
        all_changes.extend(changes)

    if not all_changes:
        print("No changes made -- all 4 required manual hooks already present.")


if __name__ == "__main__":
    main()
