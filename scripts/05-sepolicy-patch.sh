#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../config.env
source lib.sh
require_source_root

DTREE="$SOURCE_ROOT/$DEVICE_TREE_PATH"
[[ -d "$DTREE" ]] || die "Device tree not found at $DTREE — run 02-clone-device-trees.sh first."

SEPOLICY_DIR="$DTREE/sepolicy/vendor"
RULE_FILE="$SEPOLICY_DIR/genfscon_axion.te"

mkdir -p "$SEPOLICY_DIR"

if [[ -f "$RULE_FILE" ]]; then
  ok "Axion sepolicy rules already written to $RULE_FILE — skipping."
else
  log "Writing Axion performance-tuning SELinux rules to $RULE_FILE"
  cat <<'EOF' > "$RULE_FILE"
# AxionOS performance tuning SELinux rules.
# Coral has no official Axion maintainer, so these aren't baked into the
# stock LineageOS device tree — added here manually.
# NOTE: verify against AxionOS/android's current README before relying on this;
# their exact required rules can change between releases.
genfscon proc /sys/vm/dirty_writeback_centisecs u:object_r:proc_dirty:s0
genfscon proc /sys/vm/vfs_cache_pressure u:object_r:proc_drop_caches:s0
genfscon proc /sys/vm/dirty_ratio u:object_r:proc_dirty:s0
genfscon proc /sys/kernel/sched_migration_cost_ns u:object_r:proc_sched:s0
EOF
  ok "Rules written."
fi

warn "Double-check that $DTREE's BoardConfig/device makefile actually includes"
warn "$SEPOLICY_DIR in BOARD_SEPOLICY_DIRS / BOARD_VENDOR_SEPOLICY_DIRS —"
warn "this script writes the file but can't safely auto-edit your makefiles for you."
