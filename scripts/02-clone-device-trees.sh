#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../config.env
source lib.sh
require_source_root

clone_component() {
  local name="$1" url="$2" target="$3" branch

  if [[ -d "$target/.git" ]]; then
    ok "$name already present, skipping."
    return 0
  fi

  log "Checking available branches for $name ($url)..."
  if branch="$(find_working_branch "$url")"; then
    ok "$name: using branch $branch"
    clone_if_missing "$url" "$branch" "$target"
  else
    err "$name: none of (${BRANCH_FALLBACKS[*]}) exist on $url"
    err "  -> Open $url on GitHub, check the Branches dropdown yourself,"
    err "     then either edit BRANCH_FALLBACKS in config.env and re-run,"
    err "     or clone it manually into $target."
    return 1
  fi
}

failures=0
clone_component "device tree" "$DEVICE_TREE_URL" "$DEVICE_TREE_PATH" || ((failures++))
clone_component "kernel tree" "$KERNEL_TREE_URL" "$KERNEL_TREE_PATH" || ((failures++))
clone_component "vendor tree" "$VENDOR_TREE_URL" "$VENDOR_TREE_PATH" || ((failures++))

if ((failures > 0)); then
  warn "$failures component(s) need manual attention (see errors above)."
  warn "If the vendor tree has no matching branch, the fallback is extracting"
  warn "blobs yourself: cd $DEVICE_TREE_PATH && ./extract-files.py"
  exit 1
fi

ok "All device components present."
