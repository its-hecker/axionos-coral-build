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
  setup       git identity + gitcookies check           (00-setup-git.sh)
  sync        repo init + repo sync AxionOS manifest     (01-sync-source.sh)
  trees       clone device/kernel/vendor trees           (02-clone-device-trees.sh)
  keys        generate + backup signing keys             (03-keygen.sh)
  ksu         integrate KernelSU-Next + SUSFS             (04-ksu-susfs.sh)
  sepolicy    add Axion's required SELinux rules          (05-sepolicy-patch.sh)
  build       breakfast + brunch                         (06-build.sh)
  all         run every step above in order

Each step is safe to re-run — already-completed work is skipped, so if a
step fails partway you can fix the issue and re-run just that step (or 'all')
without redoing earlier slow steps like sync.
EOF
}

run_step() {
  local name="$1" script="$2"
  echo
  echo "======================================================"
  echo " Step: $name"
  echo "======================================================"
  bash "scripts/$script"
}

case "$STEP" in
  setup)    run_step "git setup"        "00-setup-git.sh" ;;
  sync)     run_step "source sync"      "01-sync-source.sh" ;;
  trees)    run_step "device trees"     "02-clone-device-trees.sh" ;;
  keys)     run_step "signing keys"     "03-keygen.sh" ;;
  ksu)      run_step "KSU-Next+SUSFS"   "04-ksu-susfs.sh" ;;
  sepolicy) run_step "sepolicy patch"   "05-sepolicy-patch.sh" ;;
  build)    run_step "build"            "06-build.sh" ;;
  all)
    run_step "git setup"        "00-setup-git.sh"
    run_step "source sync"      "01-sync-source.sh"
    run_step "device trees"     "02-clone-device-trees.sh"
    run_step "signing keys"     "03-keygen.sh"
    run_step "KSU-Next+SUSFS"   "04-ksu-susfs.sh"
    run_step "sepolicy patch"   "05-sepolicy-patch.sh"
    run_step "build"            "06-build.sh"
    ;;
  *)
    usage
    exit 1
    ;;
esac
