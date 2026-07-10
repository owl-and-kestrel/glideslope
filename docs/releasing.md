# Glideslope Release Channel

Glideslope uses Sparkle as its executable update authority and a dedicated
Cloudflare R2 hostname as its stable distribution boundary. Plumage, O+K
Release/Trust, and Chirp may describe or announce a release, but none is in the
installed app's update-fetch or verification path.

Current release identity:

- app version: `0.4.0`
- build: `8`
- bundle identifier: `com.owlandkestrel.glideslope`
- update channel: `stable`
- Sparkle: exact version `2.9.4`
- feed: `https://updates.owlandkestrel.com/glideslope/stable/appcast.xml`
- R2 bucket: `ok-release-artifacts`

`package.json` is the version and monotonic-build authority. Release bundle
generation embeds both values, the stable feed URL, and the Sparkle public key
in `Info.plist`.

## Distribution Boundary

The R2 object layout is:

```text
ok-release-artifacts/
└── glideslope/
    ├── stable/
    │   └── appcast.xml
    └── releases/
        └── v<version>/
            └── <sha256>/
                └── Glideslope.zip
```

Release archives are content-addressed and immutable. Never replace the bytes
at an existing release URL. `stable/appcast.xml` is the one mutable channel
pointer and is published only after its referenced archive is publicly readable
and verified.

Bootstrap state as of 2026-07-10:

- R2 bucket `ok-release-artifacts` exists.
- The public `r2.dev` URL is disabled.
- Custom domain `updates.owlandkestrel.com` is enabled, ownership is active, and
  its minimum TLS version is 1.2.
- Cloudflare reports the custom-domain certificate as `active`; HTTPS reaches
  the dedicated bucket. A successful artifact and feed readback remains a hard
  gate for every release.
- Chirp channel `glideslope-updates` exists and is active. Initialization
  record: `msg_2dbcb564d6a24859bebe0323be04a343`.
- Stable `0.4.0` build `8` is recorded in the O+K release ledger as publication
  `rpub_4138f9b8-9a57-492f-b7fa-28415ef854aa`; an identical retry replays that
  immutable receipt rather than creating another publication.

## Sparkle Trust Authority

Sparkle's Ed25519 key is the installed app's update identity. The public key is
committed at:

```text
config/sparkle-ed25519.pub
```

The private key's canonical copy is a macOS Keychain generic-password item with:

```text
service: https://sparkle-project.org
account: owl-kestrel
```

The noninteractive packager reads a mode-`0600` export at:

```text
~/.config/owl-kestrel/secrets/sparkle-ed25519-private-key
```

Create or refresh that export without displaying the secret:

```sh
install -d -m 700 ~/.config/owl-kestrel/secrets
umask 077
key_export="$(mktemp -t glideslope-sparkle-key)"
trap 'rm -f "$key_export"' EXIT
security find-generic-password \
  -s https://sparkle-project.org \
  -a owl-kestrel \
  -w > "$key_export"
install -m 600 "$key_export" \
  ~/.config/owl-kestrel/secrets/sparkle-ed25519-private-key
```

Never print, commit, upload, paste, or include the private key in an app bundle,
release archive, manifest, log, or shell trace. Keep the Keychain item as the
canonical copy; the file is a local packaging export only.

The Sparkle Ed25519 authority is independent of the O+K P-256 provenance key at
`config/ok-release-p256-v1.pub.pem`. Sparkle verifies the signed appcast and
archive before installation. O+K Trust may additionally carry a signed
`ok.product-update.v1` envelope through the typed release ledger, but that
envelope is secondary provenance and cannot authorize executable replacement.

## Installed-App Behavior

Release builds default to automatic update checks, downloads, and installation.
They embed these relevant Sparkle fields:

```text
SUFeedURL=https://updates.owlandkestrel.com/glideslope/stable/appcast.xml
SUPublicEDKey=<contents of config/sparkle-ed25519.pub>
SUEnableAutomaticChecks=true
SUAutomaticallyUpdate=true
SUAllowsAutomaticUpdates=true
SUScheduledCheckInterval=86400
SUVerifyUpdateBeforeExtraction=true
SURequireSignedFeed=true
SUSignedFeedFailureExpirationInterval=0
```

The menu item **Install Updates Automatically** is an installation opt-out. It
changes Sparkle's automatic-download/install preference but deliberately leaves
scheduled checks enabled, so manual-install users still learn that a release is
available. **Check for Updates…** always performs an explicit Sparkle check.

Debug builds embed `SUEnableAutomaticChecks=false` and
`SUAutomaticallyUpdate=false`. They may check explicitly, but must not replace
themselves from the public stable channel in the background.

Update requests go only to the public HTTPS feed and archive URLs. They do not
contain Codex or Claude credentials, usage readings, an O+K account, a Chirp
credential, or a Plumage session.

## Technical-Alpha Installation And Apple Transition

The current technical alpha is ad-hoc signed, not Developer ID signed or
notarized. A first browser-downloaded installation may therefore be blocked by
Gatekeeper. The user must make the one-time macOS override through **System
Settings → Privacy & Security → Open Anyway**.

Versions installed before Sparkle was embedded cannot be pulled forward by the
new updater. Those users need one manual bridge installation of the first
Sparkle-enabled release. After that, the pinned Ed25519 key and stable feed can
carry them forward automatically.

When an Apple Developer account becomes available, keep all of these stable:

- bundle identifier `com.owlandkestrel.glideslope`
- `SUFeedURL`
- Sparkle Ed25519 key

Add Developer ID signing and notarization to a later archive delivered through
this same channel. Do not rotate the Sparkle Ed25519 key in the same release that
introduces Developer ID: changing both trust anchors at once makes diagnosis and
recovery unnecessarily ambiguous. If the Sparkle key ever needs planned
rotation, first ship an update authorized by the old key that embeds the new
public key.

## Prepare A Release

Start from a clean intended commit and run the full verification:

```sh
npm test
npm run test:swift
npm run build:native
```

Set release notes and package the current version:

```sh
GLIDESLOPE_RELEASE_NOTES="Describe the user-visible changes." \
  npm run package:release
```

The packager creates a release build, verifies its source provenance and
ad-hoc signature, signs the archive and appcast with Sparkle's Ed25519 key, and
then verifies both signatures. Expected outputs:

```text
dist/release/Glideslope.zip
dist/release/Glideslope.zip.sha256
dist/release/appcast.xml
dist/release/Glideslope.md
dist/release/glideslope-update.payload.json
dist/release/glideslope-update.json
dist/release/RELEASE_NOTES.txt
```

When `OK_RELEASE_PRIVATE_KEY_PEM` is set, packaging also wraps the provenance
payload as `ok.signed-manifest.v1` using the canonical O+K signer. Without it,
the provenance manifest is an unsigned local preview; that does not weaken the
separate Sparkle signature, but stable Trust publication should still require
the O+K provenance signature.

## Publish The Release

The publisher owns the entire transaction. First inspect its secret-free,
mutation-free plan:

```sh
npm run release:dry-run
```

Then provide mode-`0600` credential files and publish:

```sh
GLIDESLOPE_RELEASE_API_KEY_FILE=/secure/path/release-publisher-key.txt \
GLIDESLOPE_CHIRP_API_KEY_FILE=/secure/path/chirp-key.txt \
  npm run release:publish
```

Before its first write, the publisher validates the manifest, exact appcast
shape, content-addressed URL, ZIP length and SHA-256, both Sparkle signatures,
all credentials, and the live feed's monotonic build. It then uploads and reads
back the immutable archive, publishes and reads back the appcast, and only then
publishes the signed envelope through O+K Release/Trust and then Chirp. A retry
accepts an identical existing object/feed and replays the same ledger receipt,
but refuses different bytes at the same artifact key or build.

### Manual recovery procedure

The commands below expose the publisher's R2 portion for disaster recovery and
diagnosis. They are not an alternate routine release path.

Upload the immutable archive first. Derive its destination from the packaged
metadata rather than typing the hash by hand:

```sh
VERSION="$(plutil -extract version raw -o - package.json)"
SHA256="$(awk '{print $1}' dist/release/Glideslope.zip.sha256)"
ARTIFACT_KEY="glideslope/releases/v${VERSION}/${SHA256}/Glideslope.zip"

wrangler r2 object put \
  "ok-release-artifacts/${ARTIFACT_KEY}" \
  --file dist/release/Glideslope.zip \
  --content-type application/zip \
  --cache-control 'public,max-age=31536000,immutable' \
  --remote
```

Read it back over the public hostname and verify exact bytes before advancing
the feed:

```sh
curl -fsS \
  "https://updates.owlandkestrel.com/${ARTIFACT_KEY}" \
  -o /tmp/Glideslope-release-readback.zip
printf '%s  %s\n' "$SHA256" /tmp/Glideslope-release-readback.zip | shasum -a 256 -c -
rm /tmp/Glideslope-release-readback.zip
```

Only then upload the signed appcast:

```sh
wrangler r2 object put \
  ok-release-artifacts/glideslope/stable/appcast.xml \
  --file dist/release/appcast.xml \
  --content-type application/rss+xml \
  --cache-control 'public,max-age=300,must-revalidate' \
  --remote
```

Read the appcast back, verify its signature, and confirm its enclosure names the
expected artifact URL and build:

```sh
curl -fsS \
  https://updates.owlandkestrel.com/glideslope/stable/appcast.xml \
  -o /tmp/glideslope-appcast.xml

.build/artifacts/sparkle/Sparkle/bin/sign_update \
  --ed-key-file ~/.config/owl-kestrel/secrets/sparkle-ed25519-private-key \
  --verify /tmp/glideslope-appcast.xml

xmllint --xpath 'string(//*[local-name()="enclosure"]/@url)' \
  /tmp/glideslope-appcast.xml
xmllint --xpath 'string(//*[local-name()="version"])' \
  /tmp/glideslope-appcast.xml
rm /tmp/glideslope-appcast.xml
```

Expected values for the current release are the content-addressed `0.4.0`
archive URL and build `8`. Stop if public readback, signature verification, URL,
or build differs.

## Publication Ordering And Secondary Signals

The complete order is an invariant:

1. Upload the immutable archive.
2. Read it back and verify SHA-256.
3. Upload `stable/appcast.xml` last.
4. Read it back and verify the signed feed, enclosure URL, and build.
5. Publish the signed envelope to O+K's append-only Release/Trust ledger.
6. Emit the deduplicated `product.release_available` event to Chirp channel
   `glideslope-updates`.

Release/Trust is useful provenance and catalog metadata, but it is not the
updater's source of truth. Moving auth into Plumage must not change or proxy the
feed hostname. Installed apps never poll Chirp; Chirp remains publisher-side
fan-out for humans and operators.

The publisher validates package version, build metadata, app and bundle ids,
channel, exact source commit, clean/dirty provenance, archive SHA-256, appcast
SHA-256 and enclosure metadata, both Sparkle signatures, and the O+K P-256
envelope before any remote write. Stable publication refuses a dirty source or
unsigned provenance envelope unless an explicit unsafe rehearsal flag is
supplied. Chirp's dedupe key includes channel, version, build, and artifact
digest, so retrying after an announcement failure is safe.

## Release And Rollback Checklist

Before publication:

- Confirm version `0.4.0`, build `8`, source commit, and intended clean tree.
- Confirm `codesign --verify --deep --strict dist/Glideslope.app` succeeds.
- Confirm the packaged feed and archive signatures verify.
- Install the ZIP on a separate Mac and test launch, usage-cache recovery,
  **Check for Updates…**, and the automatic-install opt-out.
- Complete the archive-first/appcast-last R2 readback sequence.
- Run `release:dry-run` and review both secondary payloads.

After publication:

- Check from the previous Sparkle-enabled version and confirm automatic update.
- Confirm opting out of **Install Updates Automatically** preserves scheduled
  update checks.
- Read the Release/Trust channel and confirm version, artifact URL, and digest.
- Read `glideslope-updates` and confirm exactly one release event.

If a release must be withdrawn, remove or replace the mutable appcast entry and
revoke/unpublish its Trust projection. Keep the append-only release publication
as historical evidence. Do not point the same immutable URL or version
at different bytes. Publish corrected bytes under a higher build/version and a
new content-addressed URL; installed clients must never be asked to accept a
rollback.
