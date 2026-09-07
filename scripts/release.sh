#!/usr/bin/env bash
# Produces only a verified, notarized distribution archive. Never publishes it.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
: "${CONSTELLATION_SIGNING_IDENTITY:?Set a Developer ID Application identity}"
: "${CONSTELLATION_NOTARY_PROFILE:?Set a notarytool keychain profile}"
if [[ "$CONSTELLATION_SIGNING_IDENTITY" != 'Developer ID Application: '* ]]; then
  echo 'Distribution requires a Developer ID Application identity.' >&2
  exit 2
fi
./scripts/build-app.sh --universal
APP="$PROJECT_ROOT/.build/ConstellationBar.app"
lipo "$APP/Contents/MacOS/ConstellationBar" -verify_arch arm64 x86_64
codesign --verify --strict "$APP"
STAGING_DIR="$(mktemp -d "$PROJECT_ROOT/.build/notary.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGING_DIR/submission.zip"
NOTARY_ARGS=(--keychain-profile "$CONSTELLATION_NOTARY_PROFILE")
if [[ -n "${CONSTELLATION_NOTARY_KEYCHAIN:-}" ]]; then
  NOTARY_ARGS+=(--keychain "$CONSTELLATION_NOTARY_KEYCHAIN")
fi
xcrun notarytool submit "$STAGING_DIR/submission.zip" "${NOTARY_ARGS[@]}" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --strict "$APP"
spctl --assess --type execute --verbose "$APP"
# Publishable files are written only after all distribution checks succeed.
ARCHIVE="ConstellationBar-$(cat VERSION)-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGING_DIR/$ARCHIVE"
(cd "$STAGING_DIR" && shasum -a 256 "$ARCHIVE" > SHA256SUMS)
mkdir -p .build/distribution
mv "$STAGING_DIR/$ARCHIVE" .build/distribution/
mv "$STAGING_DIR/SHA256SUMS" .build/distribution/
echo "$PROJECT_ROOT/.build/distribution/$ARCHIVE"
