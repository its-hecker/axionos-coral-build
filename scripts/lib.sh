#!/usr/bin/env bash
# Shared helpers. Sourced by every scripts/NN-*.sh — not run directly.

C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[1;33m'; C_RED='\033[0;31m'; C_CYAN='\033[0;36m'

log()  { echo -e "${C_CYAN}[INFO]${C_RESET} $*"; }
ok()   { echo -e "${C_GREEN}[OK]${C_RESET} $*"; }
warn() { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
err()  { echo -e "${C_RED}[ERROR]${C_RESET} $*" >&2; }
die()  { err "$*"; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

# find_working_branch <repo_url> -> prints the first branch from
# BRANCH_FALLBACKS that actually exists on that remote, or returns 1
find_working_branch() {
  local url="$1" b
  for b in "${BRANCH_FALLBACKS[@]}"; do
    if git ls-remote --exit-code --heads "$url" "$b" >/dev/null 2>&1; then
      echo "$b"
      return 0
    fi
  done
  return 1
}

# clone_if_missing <url> <branch> <target_path>
clone_if_missing() {
  local url="$1" branch="$2" target="$3"
  if [[ -d "$target/.git" ]]; then
    ok "Already present, skipping clone: $target"
    return 0
  fi
  log "Cloning $url [$branch] -> $target"
  mkdir -p "$(dirname "$target")"
  git clone --depth=1 --branch "$branch" --single-branch "$url" "$target"
}

require_source_root() {
  [[ -d "$SOURCE_ROOT" ]] || die "Source root $SOURCE_ROOT does not exist yet. Run 01-sync-source.sh first."
  cd "$SOURCE_ROOT"
}
