#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../config.env
source lib.sh
require_source_root

if [[ -d vendor/lineage-priv/keys ]]; then
  ok "Keys already exist at vendor/lineage-priv/keys — skipping generation."
  ok "(delete that folder first if you want to regenerate)"
  exit 0
fi

need_cmd make

# AxionOS ships its own key-generation helper (gk -s) via envsetup.sh,
# rather than needing a manual make_key loop.
log "Sourcing envsetup.sh to get the gk helper"
# AOSP's envsetup.sh references unset vars (e.g. TOP) internally and isn't
# written to be `set -u` safe — sourcing it under strict mode throws
# "TOP: unbound variable" and can leave gk writing keys to / instead of
# vendor/lineage-priv/keys. Relax strict mode just for the source.
set +u
# shellcheck disable=SC1091
source build/envsetup.sh
set -u

log "Generating signing keys with: gk -s"
gk -s || die "gk -s failed — check that build/envsetup.sh sourced correctly and try again."

[[ -f vendor/lineage-priv/keys/releasekey.pk8 ]] || die "gk -s finished but vendor/lineage-priv/keys/releasekey.pk8 wasn't created — check its output above for permission-denied errors (often means envsetup.sh didn't fully initialize)."

mkdir -p "$KEYS_BACKUP_DIR"
cp -r vendor/lineage-priv/keys "$KEYS_BACKUP_DIR/coral-keys-$(date +%Y%m%d-%H%M%S)"
ok "Keys generated and backed up to $KEYS_BACKUP_DIR/"
warn "Also copy $KEYS_BACKUP_DIR off this server before your rental expires — storage is wiped on plan expiry."
warn "If builds aren't signed, add: -include vendor/lineage-priv/keys/keys.mk to your device mk file."
