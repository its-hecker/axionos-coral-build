#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../config.env
source lib.sh
require_source_root

LOGFILE="$SOURCE_ROOT/build-$(date +%Y%m%d-%H%M%S).log"
log "Sourcing envsetup.sh"
# AOSP's envsetup.sh - and AxionOS's own axion/ax wrapper functions on top
# of it - reference unset variables internally (envsetup.sh: TOP; axion/ax:
# BUILD_VAR_CACHE_READY, seen when lunch's cached config is invalidated by
# a source-tree change and it has to re-derive it) and none of it was
# written to be `set -u` safe. Relax strict mode for the whole AOSP-tooling
# section below rather than chasing each unbound variable individually -
# re-enabling `-u` right after the source (as earlier versions of this
# script did) just moves the crash into whichever wrapper function runs
# next.
set +u
# shellcheck disable=SC1091
source build/envsetup.sh

# AxionOS ships its own build wrapper (axion/ax) rather than stock
# breakfast/brunch - using breakfast/brunch here would silently build
# against the wrong target config.
# GMS_VARIANT (set in config.env) picks Gapps level: gms/full, pico, core,
# or va/vanilla for no Google apps at all.
log "axion $DEVICE_CODENAME userdebug $GMS_VARIANT"
axion "$DEVICE_CODENAME" userdebug "$GMS_VARIANT"

log "Starting ax -br -j$(nproc --all) - logging to $LOGFILE"
log "This can take 25 min to a few hours. Safe to detach (byobu) and check back."
BUILD_OK=0
ax -br -j"$(nproc --all)" 2>&1 | tee "$LOGFILE" && BUILD_OK=1
set -u

if [[ "$BUILD_OK" -eq 1 ]]; then
  ok "Build finished. Output should be under out/target/product/$DEVICE_CODENAME/"
  ok "Full log: $LOGFILE"
else
  err "Build failed. Check $LOGFILE for the actual error - search it for the"
  err "first 'error:' occurrence, which is usually the real cause (later ones"
  err "are often just cascading failures from it)."
  exit 1
fi
