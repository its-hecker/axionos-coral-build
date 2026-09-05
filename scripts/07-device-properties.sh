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

warn "Double check $DEVICE_MK also has:"
warn "  TARGET_DISABLE_EPPE := true"
warn "  \$(call inherit-product, vendor/lineage/config/common_full_phone.mk)"
warn "AxionOS requires both for the About Phone section and GMS framework to work correctly."
