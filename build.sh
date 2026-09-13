#!/usr/bin/env bash
# AxionOS 2.8 (coral) build orchestrator.
# Usage: ./build.sh <step|all>
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

STEP="${1:-}"

usage() {
  cat <<'EOF'
Usage: ./build.sh <step>

Steps (run in this order the first time):
  setup         git identity + gitcookies check           (00-setup-git.sh)
  sync          repo init + repo sync AxionOS manifest     (01-sync-source.sh)
  trees         clone device/kernel/vendor trees           (02-clone-device-trees.sh)
  keys          generate + backup signing keys             (03-keygen.sh)
  ksu [--yes|--no]
                integrate KernelSU-Next + SUSFS             (04-ksu-susfs.sh)
                Root is OFF by default. With no flag and an interactive
                terminal, you'll be prompted y/N. Pass --yes or --no to
                answer non-interactively (e.g. for 'all' or a cron/CI run):
                  ./build.sh ksu --yes
                  ./build.sh all --no
  kernelrelease-fix
                shorten kernel version string (64-char fix) (08-fix-kernelrelease.sh)
                runs automatically at the end of 'ksu' -- only needed standalone
                if you want to re-apply it without redoing KSU/SUSFS integration.
  path-umount-fix
                backport path_umount() for pre-5.9 kernels    (09-fix-path-umount.sh)
                runs automatically at the end of 'ksu' -- only needed standalone
                if you want to re-apply it without redoing KSU/SUSFS integration.
  sepolicy      add Axion's required SELinux rules          (05-sepolicy-patch.sh)
  device-props  set maintainer/camera/processor properties  (07-device-properties.sh)
  build         axion + ax                                  (06-build.sh)
  all           run every step above in order

Each step is safe to re-run — already-completed work is skipped, so if a
step fails partway you can fix the issue and re-run just that step (or 'all')
without redoing earlier slow steps like sync.
EOF
}

run_step() {
  local name="$1" script="$2"
  shift 2
  # Defensive: scripts copied/scp'd onto the server (as opposed to
  # git-cloned) don't always keep their execute bit, which previously
  # caused 04-ksu-susfs.sh to abort silently under set -e on a plain
  # "Permission denied". Always ensure it's set before running anything.
  chmod +x "scripts/$script" 2>/dev/null || true
  echo
  echo "======================================================"
  echo " Step: $name"
  echo "======================================================"
  bash "scripts/$script" "$@"
}

# Any extra args after the step name (e.g. --yes / --no) are passed
# through to that step's script -- currently only used by 04-ksu-susfs.sh
# to answer its "add KSU-Next + SUSFS?" prompt non-interactively.
EXTRA_ARGS=("${@:2}")

case "$STEP" in
  setup)        run_step "git setup"         "00-setup-git.sh" ;;
  sync)         run_step "source sync"       "01-sync-source.sh" ;;
  trees)        run_step "device trees"      "02-clone-device-trees.sh" ;;
  keys)         run_step "signing keys"      "03-keygen.sh" ;;
  ksu)          run_step "KSU-Next+SUSFS"    "04-ksu-susfs.sh" "${EXTRA_ARGS[@]}" ;;
  kernelrelease-fix) run_step "kernel release length fix" "08-fix-kernelrelease.sh" ;;
  path-umount-fix)   run_step "path_umount backport"      "09-fix-path-umount.sh" ;;
  sepolicy)     run_step "sepolicy patch"    "05-sepolicy-patch.sh" ;;
  device-props) run_step "device properties" "07-device-properties.sh" ;;
  build)        run_step "build"             "06-build.sh" ;;
  all)
    run_step "git setup"         "00-setup-git.sh"
    run_step "source sync"       "01-sync-source.sh"
    run_step "device trees"      "02-clone-device-trees.sh"
    run_step "signing keys"      "03-keygen.sh"
    run_step "KSU-Next+SUSFS"    "04-ksu-susfs.sh" "${EXTRA_ARGS[@]}"
    run_step "sepolicy patch"    "05-sepolicy-patch.sh"
    run_step "device properties" "07-device-properties.sh"
    run_step "build"             "06-build.sh"
    ;;
  *)
    usage
    exit 1
    ;;
esac
