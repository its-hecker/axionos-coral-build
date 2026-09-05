# AxionOS 2.8 build automation — Pixel 4 XL (coral)

Automates the AxionOS 2.8 + KernelSU-Next + SUSFS build pipeline for coral on
a ServerHive-style rented build server. Coral is **not** an officially
maintained AxionOS device — this bridges it via the underlying LineageOS
`lineage-22.2` device tree, so expect some manual troubleshooting on the
sepolicy/kernel-patch steps.

## Usage

```bash
git clone https://github.com/<your-username>/axionos-coral-build.git
cd axionos-coral-build
chmod +x build.sh scripts/*.sh

./build.sh setup      # git identity + gitcookies reminder (one-time, manual step required)
./build.sh sync       # repo init + repo sync — the long step, hours depending on network
./build.sh trees      # clone device/kernel/vendor trees, with branch auto-fallback
./build.sh keys       # generate + back up signing keys
./build.sh ksu        # integrate KernelSU-Next + SUSFS into the kernel
./build.sh sepolicy   # add Axion's required SELinux rules (coral doesn't have these built in)
./build.sh build      # breakfast + brunch, logs to a timestamped file

# or just run everything in order:
./build.sh all
```

Every step is **idempotent** — if something fails partway (a patch doesn't
apply, a branch is missing, etc.), fix the underlying issue and re-run just
that step. It skips work that's already done rather than starting over,
so you don't lose the multi-hour sync step to a later failure.

## Configuration

All the URLs, branches, and versions live in `config.env`. If a branch
listed there stops existing upstream, add the next one to
`BRANCH_FALLBACKS` and re-run `trees` — the script checks each candidate
against the actual remote before cloning.

## What this does NOT automate

- **git cookies** (`00-setup-git.sh` only checks/reminds) — this needs an
  interactive Google login, so it can't be scripted safely.
- **Bootloader unlock** — do this on the physical device beforehand.
- **Flashing** — this pipeline only produces the build artifact; flashing
  is a separate manual step once you have the zip.
- **Uploading the finished build** — intentionally left out. If you wire up
  your own uploader, avoid a fetch-and-execute-on-every-run pattern for
  any script with API tokens in its environment — pin a version instead.

## Layout

```
build.sh                     # orchestrator — run this
config.env                   # all tunable settings
scripts/
  lib.sh                     # shared helpers (not run directly)
  00-setup-git.sh
  01-sync-source.sh
  02-clone-device-trees.sh
  03-keygen.sh
  04-ksu-susfs.sh
  05-sepolicy-patch.sh
  06-build.sh
```
