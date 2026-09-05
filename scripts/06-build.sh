#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../config.env
source lib.sh
require_source_root

LOGFILE="$SOURCE_ROOT/build-$(date +%Y%m%d-%H%M%S).log"
log "Sourcing envsetup.sh"
# shellcheck disable=SC1091
source build/envsetup.sh

# AxionOS ships its own build wrapper (axion/ax) rather than stock
# breakfast/brunch — using breakfast/brunch here would silently build
# against the wrong target config.
log "axion $DEVICE_CODENAME userdebug va"
axion "$DEVICE_CODENAME" userdebug va

log "Starting ax -br -j$(nproc --all) — logging to $LOGFILE"
log "This can take 25 min to a few hours. Safe to detach (byobu) and check back."
if ax -br -j"$(nproc --all)" 2>&1 | tee "$LOGFILE"; then
  ok "Build finished. Output should be under out/target/product/$DEVICE_CODENAME/"
  ok "Full log: $LOGFILE"
else
  err "Build failed. Check $LOGFILE for the actual error — search it for the"
  err "first 'error:' occurrence, which is usually the real cause (later ones"
  err "are often just cascading failures from it)."
  exit 1
fi
