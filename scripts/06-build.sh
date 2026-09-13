#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../config.env
source lib.sh
require_source_root

LOGFILE="$SOURCE_ROOT/build-$(date +%Y%m%d-%H%M%S).log"
log "Sourcing envsetup.sh"

# AOSP's envsetup.sh, and AxionOS's axion/ax wrapper functions built on top
# of it, are not written to be `set -e` OR `set -u` safe: they reference
# unset variables (envsetup.sh: TOP; axion/ax: BUILD_VAR_CACHE_READY) and
# routinely have internal commands (grep checks, version probes, lunch's
# cache re-derivation logic) return non-zero as completely normal control
# flow, not as a real failure. Under strict mode, either flag silently
# kills this whole script mid-function -- and *where* it dies varies from
# run to run depending on whether lunch's product-config cache happens to
# be valid or needs re-deriving (which any source-tree change, like the
# KSU/SUSFS kernel edits, invalidates). Patching one call site at a time
# just moves the crash to the next one. Relax -e and -u for this entire
# AOSP-tooling block instead, and verify success explicitly via exit codes
# the whole way through, same as this script already does for ax -br.
set +eu

source build/envsetup.sh

# AxionOS ships its own build wrapper (axion/ax) rather than stock
# breakfast/brunch - using breakfast/brunch here would silently build
# against the wrong target config.
# GMS_VARIANT (set in config.env) picks Gapps level: gms/full, pico, core,
# or va/vanilla for no Google apps at all.
log "axion $DEVICE_CODENAME userdebug $GMS_VARIANT"
axion "$DEVICE_CODENAME" userdebug "$GMS_VARIANT"
AXION_EXIT=$?

if [[ "$AXION_EXIT" -ne 0 ]]; then
  set -eu
  err "axion $DEVICE_CODENAME userdebug $GMS_VARIANT exited with status $AXION_EXIT."
  err "This is the lunch/product-config step, before any compilation starts --"
  err "it is NOT the KSU/kernel link failure from the v8 addendum. Re-run it by"
  err "hand (source build/envsetup.sh; axion $DEVICE_CODENAME userdebug $GMS_VARIANT)"
  err "and read whatever it prints right above its usage banner for the real cause."
  exit 1
fi

log "Starting ax -br -j$(nproc --all) - logging to $LOGFILE"
log "This can take 25 min to a few hours. Safe to detach (byobu) and check back."
BUILD_OK=0
ax -br -j"$(nproc --all)" 2>&1 | tee "$LOGFILE" && BUILD_OK=1
set -eu

if [[ "$BUILD_OK" -eq 1 ]]; then
  ok "Build finished. Output should be under out/target/product/$DEVICE_CODENAME/"
  ok "Full log: $LOGFILE"
else
  err "Build failed. Check $LOGFILE for the actual error - search it for the"
  err "first 'error:' occurrence, which is usually the real cause (later ones"
  err "are often just cascading failures from it)."
  exit 1
fi
