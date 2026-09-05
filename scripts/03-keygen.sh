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

subject='/C=US/ST=California/L=Mountain View/O=Android/OU=Android/CN=Android/emailAddress=android@android.com'
log "Generating signing keys with subject: $subject"

mkdir -p "$HOME/.android-certs"
for x in bluetooth media networkstack nfc platform releasekey sdk_sandbox shared testkey verifiedboot; do
  ./development/tools/make_key "$HOME/.android-certs/$x" "$subject" </dev/null || die "make_key failed for $x"
done

mkdir -p vendor/lineage-priv
mv "$HOME/.android-certs" vendor/lineage-priv/keys
echo "PRODUCT_DEFAULT_DEV_CERTIFICATE := vendor/lineage-priv/keys/releasekey" > vendor/lineage-priv/keys/keys.mk

cat <<'EOF' > vendor/lineage-priv/keys/BUILD.bazel
filegroup(
    name = "android_certificate_directory",
    srcs = glob([
        "*.pk8",
        "*.pem",
    ]),
    visibility = ["//visibility:public"],
)
EOF

mkdir -p "$KEYS_BACKUP_DIR"
cp -r vendor/lineage-priv/keys "$KEYS_BACKUP_DIR/coral-keys-$(date +%Y%m%d-%H%M%S)"
ok "Keys generated and backed up to $KEYS_BACKUP_DIR/"
warn "Also copy $KEYS_BACKUP_DIR off this server before your rental expires — storage is wiped on plan expiry."
warn "If builds aren't signed, add: -include vendor/lineage-priv/keys/keys.mk to your device mk file."
