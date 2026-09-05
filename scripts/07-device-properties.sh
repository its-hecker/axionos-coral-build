#!/usr/bin/env bash
# Writes AxionOS "About phone" device properties (maintainer, camera info,
# processor name) into the coral device tree's product makefile.
# Run after 02-clone-device-trees.sh (needs the device tree to exist) and
# before 06-build.sh.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../config.env
source lib.sh
require_source_root

DTREE="$SOURCE_ROOT/$DEVICE_TREE_PATH"
[[ -d "$DTREE" ]] || die "Device tree not found at $DTREE — run 02-clone-device-trees.sh first."

# LineageOS device trees name the product makefile lineage_<codename>.mk —
# find it rather than hardcoding, in case coral's tree differs.
DEVICE_MK="$(find "$DTREE" -maxdepth 1 -name "lineage_${DEVICE_CODENAME}.mk" | head -n1)"
if [[ -z "$DEVICE_MK" ]]; then
  DEVICE_MK="$(grep -rl "inherit-product" "$DTREE"/*.mk 2>/dev/null | head -n1 || true)"
fi
[[ -n "$DEVICE_MK" && -f "$DEVICE_MK" ]] || die "Couldn't find $DTREE's product makefile (expected lineage_${DEVICE_CODENAME}.mk). Add the block below to it by hand."

# --- Required AxionOS device-tree lines ---
# Every AxionOS device tree needs these two lines for the About Phone
# section and GMS framework to work. Not optional, unlike the properties
# block below.
if grep -q "TARGET_DISABLE_EPPE" "$DEVICE_MK"; then
  ok "Required AxionOS inherit/EPPE lines already present in $DEVICE_MK — skipping."
else
  log "Adding required AxionOS lines (TARGET_DISABLE_EPPE + inherit-product) to $DEVICE_MK"
  cat <<'EOF' >> "$DEVICE_MK"

# --- Required AxionOS lines (added by 07-device-properties.sh) ---
TARGET_DISABLE_EPPE := true
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)
EOF
  ok "Required lines added."
fi

if grep -q "AXION_MAINTAINER" "$DEVICE_MK"; then
  ok "AxionOS device properties already present in $DEVICE_MK — skipping."
else
  log "Writing AxionOS device properties to $DEVICE_MK"
  cat <<EOF >> "$DEVICE_MK"

# --- AxionOS "About phone" device properties (added by 07-device-properties.sh) ---
AXION_MAINTAINER := ${AXION_MAINTAINER}
AXION_CAMERA_REAR_INFO := ${AXION_CAMERA_REAR_INFO}
AXION_CAMERA_FRONT_INFO := ${AXION_CAMERA_FRONT_INFO}
AXION_PROCESSOR := ${AXION_PROCESSOR}
EOF
  ok "Device properties written."
fi

if grep -q "TARGET_INCLUDE_AXFX" "$DEVICE_MK"; then
  ok "AxionFx flag already present in $DEVICE_MK — skipping."
else
  log "Enabling AxionFx (TARGET_INCLUDE_AXFX) in $DEVICE_MK"
  cat <<'EOF' >> "$DEVICE_MK"

# --- AxionFx (added by 07-device-properties.sh) ---
TARGET_INCLUDE_AXFX := true
EOF
  ok "AxionFx enabled."
fi

warn "Debugging (persist.sys.ax_debug_enabled), HBM, doze flags, and the LOS-prebuilts"
warn "flag were left at AxionOS defaults (all off/disabled) — edit $DEVICE_MK by hand"
warn "if a specific one turns out to be needed (e.g. after a bootloop)."
