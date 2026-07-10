#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT/dist/release"
APP_BUNDLE="$ROOT/dist/Glideslope.app"
ZIP_PATH="$DIST_DIR/Glideslope.zip"
CHECKSUM_PATH="$ZIP_PATH.sha256"
APPCAST_PATH="$DIST_DIR/appcast.xml"
PAYLOAD_PATH="$DIST_DIR/glideslope-update.payload.json"
MANIFEST_PATH="$DIST_DIR/glideslope-update.json"
RELEASE_NOTES_PATH="$DIST_DIR/RELEASE_NOTES.txt"
SPARKLE_RELEASE_NOTES_PATH="$DIST_DIR/Glideslope.md"
RELEASE_CHANNEL="${GLIDESLOPE_RELEASE_CHANNEL:-stable}"
DOWNLOAD_PAGE_URL="${GLIDESLOPE_DOWNLOAD_PAGE_URL:-https://owlandkestrel.com/apps/glideslope}"
RELEASE_NOTES="${GLIDESLOPE_RELEASE_NOTES:-Usage reliability and update-channel improvements.}"
OK_RELEASE_SIGNER="${OK_RELEASE_SIGNER:-/Users/jon/Projects/utilities/ok-release-tools/scripts/sign-manifest.mjs}"
SPARKLE_PRIVATE_KEY_FILE="${GLIDESLOPE_SPARKLE_PRIVATE_KEY_FILE:-/Users/jon/.config/owl-kestrel/secrets/sparkle-ed25519-private-key}"
SPARKLE_GENERATE_APPCAST="$ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
SPARKLE_SIGN_UPDATE="$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"

if [[ $# -ne 0 ]]; then
  echo "usage: $0" >&2
  exit 2
fi

GLIDESLOPE_BUILD_CONFIGURATION=release \
GLIDESLOPE_UPDATE_CHANNEL="$RELEASE_CHANNEL" \
  "$ROOT/script/build_and_run.sh" --build

VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$APP_BUNDLE/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$APP_BUNDLE/Contents/Info.plist")"
MIN_SYSTEM_VERSION="$(/usr/bin/plutil -extract LSMinimumSystemVersion raw -o - "$APP_BUNDLE/Contents/Info.plist")"
ARCHITECTURES="$(/usr/bin/lipo -archs "$APP_BUNDLE/Contents/MacOS/Glideslope")"
BUILD_CONFIGURATION="$(/usr/bin/plutil -extract GlideslopeBuildConfiguration raw -o - "$APP_BUNDLE/Contents/Info.plist")"
BUNDLE_UPDATE_CHANNEL="$(/usr/bin/plutil -extract GlideslopeUpdateChannel raw -o - "$APP_BUNDLE/Contents/Info.plist")"
SPARKLE_FEED_URL="$(/usr/bin/plutil -extract SUFeedURL raw -o - "$APP_BUNDLE/Contents/Info.plist")"
SPARKLE_PUBLIC_KEY="$(/usr/bin/plutil -extract SUPublicEDKey raw -o - "$APP_BUNDLE/Contents/Info.plist")"
AUTOMATIC_CHECKS="$(/usr/bin/plutil -extract SUEnableAutomaticChecks raw -o - "$APP_BUNDLE/Contents/Info.plist")"
AUTOMATIC_INSTALLS="$(/usr/bin/plutil -extract SUAutomaticallyUpdate raw -o - "$APP_BUNDLE/Contents/Info.plist")"
SOURCE_COMMIT="$(/usr/bin/plutil -extract GlideslopeSourceCommit raw -o - "$APP_BUNDLE/Contents/Info.plist")"
SOURCE_DIRTY="$(/usr/bin/plutil -extract GlideslopeSourceDirty raw -o - "$APP_BUNDLE/Contents/Info.plist")"
PUBLISHED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
CURRENT_SOURCE_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=normal)" ]]; then
  CURRENT_SOURCE_DIRTY="true"
else
  CURRENT_SOURCE_DIRTY="false"
fi
if [[ "$BUILD_CONFIGURATION" != "release" ]]; then
  echo "Refusing to package a non-release Glideslope bundle." >&2
  exit 1
fi
if [[ "$BUNDLE_UPDATE_CHANNEL" != "$RELEASE_CHANNEL" ]]; then
  echo "Bundle update channel does not match the release channel." >&2
  exit 1
fi
EXPECTED_FEED_URL="https://updates.owlandkestrel.com/glideslope/$RELEASE_CHANNEL/appcast.xml"
if [[ "$SPARKLE_FEED_URL" != "${GLIDESLOPE_SPARKLE_FEED_URL:-$EXPECTED_FEED_URL}" ]]; then
  echo "Bundle Sparkle feed URL does not match the release feed." >&2
  exit 1
fi
if [[ "$AUTOMATIC_CHECKS" != "true" || "$AUTOMATIC_INSTALLS" != "true" ]]; then
  echo "Release bundles must default to automatic Sparkle checks and installation." >&2
  exit 1
fi
if [[ ! -f "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
  echo "Sparkle private key is missing: $SPARKLE_PRIVATE_KEY_FILE" >&2
  exit 1
fi
if [[ "$(stat -f '%Lp' "$SPARKLE_PRIVATE_KEY_FILE")" != "600" ]]; then
  echo "Sparkle private key must be mode 600." >&2
  exit 1
fi
if [[ ! -x "$SPARKLE_GENERATE_APPCAST" || ! -x "$SPARKLE_SIGN_UPDATE" ]]; then
  echo "Sparkle release tools are missing. Run swift package resolve." >&2
  exit 1
fi
if [[ "$SOURCE_COMMIT" != "$CURRENT_SOURCE_COMMIT" || "$SOURCE_DIRTY" != "$CURRENT_SOURCE_DIRTY" ]]; then
  echo "Source changed while Glideslope was building; rebuild before packaging." >&2
  exit 1
fi

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# The build script has already sealed the host app without modifying Sparkle's
# nested helpers. Never deep re-sign this bundle: that can invalidate Sparkle's
# framework, XPC services, or updater app.
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

ZIP_SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
ZIP_SIZE_BYTES="$(stat -f%z "$ZIP_PATH")"
ARTIFACT_URL="${GLIDESLOPE_RELEASE_ARTIFACT_URL:-https://updates.owlandkestrel.com/glideslope/releases/v$VERSION/$ZIP_SHA256/Glideslope.zip}"
if [[ "${ARTIFACT_URL##*/}" != "Glideslope.zip" ]]; then
  echo "Sparkle artifact URL must end in Glideslope.zip." >&2
  exit 1
fi
ARTIFACT_URL_PREFIX="${ARTIFACT_URL%/*}/"
printf '%s  %s\n' "$ZIP_SHA256" "$(basename "$ZIP_PATH")" > "$CHECKSUM_PATH"

cat > "$RELEASE_NOTES_PATH" <<NOTES
Glideslope $VERSION ($RELEASE_CHANNEL)

$RELEASE_NOTES

This alpha package is ad-hoc signed, not Developer ID signed or notarized.

Artifact:
- Glideslope.zip
- SHA-256: $ZIP_SHA256
- Size: $ZIP_SIZE_BYTES bytes
NOTES

printf '# Glideslope %s\n\n%s\n' "$VERSION" "$RELEASE_NOTES" > "$SPARKLE_RELEASE_NOTES_PATH"

# Generate and sign both the archive enclosure and the appcast using Sparkle's
# dedicated Ed25519 authority. This is the executable update trust chain; the
# O+K P-256 provenance envelope below is independent metadata.
"$SPARKLE_GENERATE_APPCAST" \
  --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
  --download-url-prefix "$ARTIFACT_URL_PREFIX" \
  --link "$DOWNLOAD_PAGE_URL" \
  --embed-release-notes \
  --maximum-versions 0 \
  --maximum-deltas 0 \
  --versions "$BUILD_NUMBER" \
  -o "$APPCAST_PATH" \
  "$DIST_DIR"

APPCAST_ARTIFACT_URL="$(/usr/bin/xmllint --xpath 'string(//*[local-name()="enclosure"]/@url)' "$APPCAST_PATH")"
APPCAST_SIGNATURE="$(/usr/bin/xmllint --xpath 'string(//*[local-name()="enclosure"]/@*[local-name()="edSignature"])' "$APPCAST_PATH")"
APPCAST_BUILD="$(/usr/bin/xmllint --xpath 'string(//*[local-name()="version"])' "$APPCAST_PATH")"
if [[ "$APPCAST_ARTIFACT_URL" != "$ARTIFACT_URL" || "$APPCAST_BUILD" != "$BUILD_NUMBER" || -z "$APPCAST_SIGNATURE" ]]; then
  echo "Generated Sparkle appcast does not match the packaged artifact and build." >&2
  exit 1
fi
"$SPARKLE_SIGN_UPDATE" \
  --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
  --verify "$ZIP_PATH" "$APPCAST_SIGNATURE"
"$SPARKLE_SIGN_UPDATE" \
  --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
  --verify "$APPCAST_PATH"
APPCAST_SHA256="$(shasum -a 256 "$APPCAST_PATH" | awk '{print $1}')"

GLIDESLOPE_VERSION="$VERSION" \
GLIDESLOPE_BUILD_NUMBER="$BUILD_NUMBER" \
GLIDESLOPE_MIN_SYSTEM_VERSION="$MIN_SYSTEM_VERSION" \
GLIDESLOPE_ARCHITECTURES="$ARCHITECTURES" \
GLIDESLOPE_PUBLISHED_AT="$PUBLISHED_AT" \
GLIDESLOPE_RELEASE_CHANNEL="$RELEASE_CHANNEL" \
GLIDESLOPE_RELEASE_NOTES="$RELEASE_NOTES" \
GLIDESLOPE_ARTIFACT_URL="$ARTIFACT_URL" \
GLIDESLOPE_ARTIFACT_SHA256="$ZIP_SHA256" \
GLIDESLOPE_ARTIFACT_SIZE_BYTES="$ZIP_SIZE_BYTES" \
GLIDESLOPE_APPCAST_URL="$SPARKLE_FEED_URL" \
GLIDESLOPE_APPCAST_SHA256="$APPCAST_SHA256" \
GLIDESLOPE_SPARKLE_PUBLIC_KEY="$SPARKLE_PUBLIC_KEY" \
GLIDESLOPE_DOWNLOAD_PAGE_URL="$DOWNLOAD_PAGE_URL" \
GLIDESLOPE_SOURCE_COMMIT="$SOURCE_COMMIT" \
GLIDESLOPE_SOURCE_DIRTY="$SOURCE_DIRTY" \
GLIDESLOPE_SOURCE_BUILD_CONFIGURATION="$BUILD_CONFIGURATION" \
node <<'NODE' > "$PAYLOAD_PATH"
const payload = {
  schema: "ok.product-update.v1",
  appId: "glideslope",
  bundleId: "com.owlandkestrel.glideslope",
  version: process.env.GLIDESLOPE_VERSION,
  build: Number(process.env.GLIDESLOPE_BUILD_NUMBER),
  channel: process.env.GLIDESLOPE_RELEASE_CHANNEL,
  minimumSystemVersion: process.env.GLIDESLOPE_MIN_SYSTEM_VERSION,
  publishedAt: process.env.GLIDESLOPE_PUBLISHED_AT,
  releaseNotes: process.env.GLIDESLOPE_RELEASE_NOTES,
  downloadPageUrl: process.env.GLIDESLOPE_DOWNLOAD_PAGE_URL,
  updateFeed: {
    format: "sparkle.appcast.v2",
    url: process.env.GLIDESLOPE_APPCAST_URL,
    sha256: process.env.GLIDESLOPE_APPCAST_SHA256,
    publicKey: process.env.GLIDESLOPE_SPARKLE_PUBLIC_KEY,
    automaticByDefault: true
  },
  source: {
    repository: "https://github.com/owl-and-kestrel/glideslope.git",
    commit: process.env.GLIDESLOPE_SOURCE_COMMIT,
    dirty: process.env.GLIDESLOPE_SOURCE_DIRTY === "true",
    buildConfiguration: process.env.GLIDESLOPE_SOURCE_BUILD_CONFIGURATION
  },
  artifacts: [{
    platform: "macos",
    architectures: process.env.GLIDESLOPE_ARCHITECTURES.split(/\s+/u).filter(Boolean),
    url: process.env.GLIDESLOPE_ARTIFACT_URL,
    sha256: process.env.GLIDESLOPE_ARTIFACT_SHA256,
    sizeBytes: Number(process.env.GLIDESLOPE_ARTIFACT_SIZE_BYTES)
  }]
};

process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
NODE

if [[ -n "${OK_RELEASE_PRIVATE_KEY_PEM:-}" ]]; then
  if [[ ! -f "$OK_RELEASE_SIGNER" ]]; then
    echo "O+K release signer not found: $OK_RELEASE_SIGNER" >&2
    exit 1
  fi
  OK_RELEASE_PUBLISHER_ID="${OK_RELEASE_PUBLISHER_ID:-owl-kestrel}" \
  OK_RELEASE_PUBLISHER_NAME="${OK_RELEASE_PUBLISHER_NAME:-Owl & Kestrel}" \
  OK_RELEASE_PUBLISHER_DOMAIN="${OK_RELEASE_PUBLISHER_DOMAIN:-owlandkestrel.com}" \
  OK_RELEASE_KEY_ID="${OK_RELEASE_KEY_ID:-ok-release-p256-v1}" \
  node "$OK_RELEASE_SIGNER" "$PAYLOAD_PATH" "$MANIFEST_PATH"
else
  cp "$PAYLOAD_PATH" "$MANIFEST_PATH"
fi

echo "Created $ZIP_PATH"
echo "Wrote $CHECKSUM_PATH"
echo "Wrote $APPCAST_PATH"
echo "Wrote $PAYLOAD_PATH"
echo "Wrote $MANIFEST_PATH"
echo "Wrote $RELEASE_NOTES_PATH"
