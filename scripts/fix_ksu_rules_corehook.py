#!/usr/bin/env python3
"""
Targeted, idempotent fix for the KernelSU-Next v1.1.1 + SUSFS link failure.

Root cause (confirmed by reproducing the setup.sh + patch apply locally):
  v1.1.1 upstream already renamed a few internal helpers on its own
  (getenforce -> ksu_getenforce, is_zygote -> ksu_is_zygote, both now
  defined in selinux/selinux.c) and shifted surrounding code (e.g. an
  extra `static DEFINE_MUTEX(ksu_rules);` line in rules.c) enough that
  the pinned SUSFS support patch's context no longer matches. patch(1)
  therefore rejects rules.c entirely (3/3 hunks) and two hunks in
  core_hook.c (the is_allow_su() rename and the do_umount rename
  block), leaving a handful of call sites still using the old,
  now-undefined names:

    rules.c:      apply_kernelsu_rules, getenforce(), handle_sepolicy
    core_hook.c:  is_manager() (in is_allow_su), is_zygote(), try_umount(

  This script renames exactly those leftover call sites/definitions to
  the names the rest of the (successfully-patched) tree already
  expects. It does not attempt to re-synthesize the failed patch hunks
  themselves, and does not touch anything already renamed.

Every substitution is scoped with \b word boundaries. Because the
already-correct names all have a "ksu_" or "susfs_" prefix ending in
"_", a word boundary never falls between the prefix and the bare name,
so plain \bname\b regexes cannot double-rename anything -- no negative
lookbehind is needed. Idempotent: if a pattern is already gone, it's a
no-op.
"""
import re
import sys


def count(pattern, src):
    return len(re.findall(pattern, src))


def fix_rules_c(path):
    with open(path) as f:
        src = f.read()
    original = src
    changes = []

    # 1. void apply_kernelsu_rules() -> void ksu_apply_kernelsu_rules()
    pat = re.compile(r'\bvoid\s+apply_kernelsu_rules\s*\(\s*\)')
    n = count(pat, src)
    if n:
        src = pat.sub('void ksu_apply_kernelsu_rules()', src)
        changes.append(f"renamed apply_kernelsu_rules definition ({n})")

    # 2. getenforce() -> ksu_getenforce() (bare calls only)
    pat = re.compile(r'\bgetenforce\s*\(\s*\)')
    n = count(pat, src)
    if n:
        src = pat.sub('ksu_getenforce()', src)
        changes.append(f"renamed getenforce() calls ({n})")

    # 3. int handle_sepolicy(...) -> int ksu_handle_sepolicy(...)
    pat = re.compile(
        r'\bint\s+handle_sepolicy\s*\(\s*unsigned\s+long\s+arg3\s*,\s*'
        r'void\s+__user\s*\*\s*arg4\s*\)'
    )
    n = count(pat, src)
    if n:
        src = pat.sub(
            'int ksu_handle_sepolicy(unsigned long arg3, void __user *arg4)',
            src,
        )
        changes.append(f"renamed handle_sepolicy definition ({n})")

    # 4. Insert the SUSFS zygote-unmount SELinux permission block, once,
    #    right after the sigkill allow rule and before rcu_read_unlock().
    marker = 'ksu_allow(db, "system_server", KERNEL_SU_DOMAIN, "process", "sigkill");'
    already_present = 'susfs_set_zygote_sid' in src
    if marker in src and not already_present:
        block = (
            marker
            + "\n\n#ifdef CONFIG_KSU_SUSFS\n"
            "\t// Allow umount in zygote process without installing zygisk\n"
            '\tksu_allow(db, "zygote", "labeledfs", "filesystem", "unmount");\n'
            "\tsusfs_set_init_sid();\n"
            "\tsusfs_set_ksu_sid();\n"
            "\tsusfs_set_zygote_sid();\n"
            "#endif\n"
        )
        src = src.replace(marker, block, 1)
        changes.append("inserted SUSFS zygote-unmount SELinux block")

    if src != original:
        with open(path, 'w') as f:
            f.write(src)
    return changes


def fix_core_hook_c(path):
    with open(path) as f:
        src = f.read()
    original = src
    changes = []

    # 1. is_manager() -> ksu_is_manager() (bare calls only; the "ksu_is_manager"
    #    call sites already introduced by successful hunks are untouched
    #    because \b never falls between "_" and "i").
    pat = re.compile(r'\bis_manager\s*\(\s*\)')
    n = count(pat, src)
    if n:
        src = pat.sub('ksu_is_manager()', src)
        changes.append(f"renamed is_manager() calls ({n})")

    # 2. is_zygote(...) -> ksu_is_zygote(...)
    pat = re.compile(r'\bis_zygote\s*\(')
    n = count(pat, src)
    if n:
        src = pat.sub('ksu_is_zygote(', src)
        changes.append(f"renamed is_zygote() calls ({n})")

    # 3. try_umount(...) -> ksu_try_umount(...) (bare calls only; does not
    #    match ksu_try_umount(, susfs_try_umount(, or the
    #    out_ksu_try_umount: label, since none of those have a word
    #    boundary immediately before "try_umount").
    pat = re.compile(r'\btry_umount\s*\(')
    n = count(pat, src)
    if n:
        src = pat.sub('ksu_try_umount(', src)
        changes.append(f"renamed try_umount() calls ({n})")

    if src != original:
        with open(path, 'w') as f:
            f.write(src)
    return changes


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <rules.c path> <core_hook.c path>", file=sys.stderr)
        sys.exit(1)
    rules_path, core_hook_path = sys.argv[1], sys.argv[2]

    all_changes = []
    all_changes += [("rules.c", c) for c in fix_rules_c(rules_path)]
    all_changes += [("core_hook.c", c) for c in fix_core_hook_c(core_hook_path)]

    if not all_changes:
        print("No leftover old-name call sites found -- nothing to do (already fixed, or upstream changed).")
        return

    for fname, change in all_changes:
        print(f"[{fname}] {change}")


if __name__ == "__main__":
    main()
