#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../config.env
source lib.sh

need_cmd git

if [[ -z "$(git config --global user.name || true)" ]]; then
  read -r -p "Git user.name: " gname
  git config --global user.name "$gname"
fi
if [[ -z "$(git config --global user.email || true)" ]]; then
  read -r -p "Git user.email: " gmail
  git config --global user.email "$gmail"
fi
ok "Git identity: $(git config --global user.name) <$(git config --global user.email)>"

if [[ -f "$HOME/.gitcookies" ]]; then
  ok "Found existing ~/.gitcookies — Google source syncs should avoid rate limits."
else
  warn "No ~/.gitcookies found."
  warn "This is a one-time manual step — it needs your Google login, so it can't be scripted:"
  warn "  1. Visit https://android.googlesource.com/ in a browser"
  warn "  2. Click 'Generate Password', sign in, follow 'Configure Git'"
  warn "  3. Paste the script it gives you into THIS shell (not local PowerShell)"
  warn "Re-run this script after to confirm it landed."
fi
