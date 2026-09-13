#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../config.env
source lib.sh

need_cmd repo
need_cmd git

mkdir -p "$SOURCE_ROOT"
cd "$SOURCE_ROOT"

if [[ -d .repo ]]; then
  ok "Repo already initialized in $SOURCE_ROOT — skipping repo init."
else
  log "repo init -> $MANIFEST_URL [$MANIFEST_BRANCH]"
  repo init -u "$MANIFEST_URL" -b "$MANIFEST_BRANCH" --git-lfs
fi

log "Starting repo sync — this is the long step, expect 1-4+ hours depending on network."
log "Safe to detach (byobu) once this is running; it keeps going in the background."
repo sync -c -j"$(nproc --all)" --force-sync --no-clone-bundle --no-tags --optimized-fetch --prune

ok "Base source sync complete."
