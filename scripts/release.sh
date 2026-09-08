#!/usr/bin/env bash
# Produces only a verified, notarized distribution archive. Never publishes it.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
: "${CONSTELLATION_SIGNING_IDENTITY:?Set a Developer ID Application identity}"
CONSTELLATION_NOTARY_PROFILE="${CONSTELLATION_NOTARY_PROFILE:-constellation-release}"
if [[ "$CONSTELLATION_SIGNING_IDENTITY" != 'Developer ID Application: '* ]]; then
  echo 'Distribution requires a Developer ID Application identity.' >&2
  exit 2
fi
NOTARY_ARGS=(--keychain-profile "$CONSTELLATION_NOTARY_PROFILE")
if [[ -n "${CONSTELLATION_NOTARY_KEYCHAIN:-}" ]]; then
  NOTARY_ARGS+=(--keychain "$CONSTELLATION_NOTARY_KEYCHAIN")
fi
mkdir -p .build
STAGING_DIR="$(mktemp -d "$PROJECT_ROOT/.build/notary.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
# Fail before a lengthy build if the account/profile is missing or invalid.
if ! xcrun notarytool history "${NOTARY_ARGS[@]}" --output-format json > "$STAGING_DIR/auth.json"; then
  echo "Notarization credentials are unavailable. Run ./scripts/setup-notarization.sh in your own terminal, or set CONSTELLATION_NOTARY_PROFILE to an existing valid profile." >&2
  exit 2
fi
./scripts/build-app.sh --universal
APP="$PROJECT_ROOT/.build/ConstellationBar.app"
lipo "$APP/Contents/MacOS/ConstellationBar" -verify_arch arm64 x86_64
codesign --verify --strict "$APP"
# Keep Apple's response and diagnostic log even when signing/notarization fails.
REPORT_DIR="$(mktemp -d "$PROJECT_ROOT/.build/notarization-report.XXXXXX")"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGING_DIR/submission.zip"
SUBMIT_EXIT=0
xcrun notarytool submit "$STAGING_DIR/submission.zip" "${NOTARY_ARGS[@]}" --wait --output-format json > "$REPORT_DIR/submission.json" || SUBMIT_EXIT=$?
SUBMISSION_ID="$(python3 - "$REPORT_DIR/submission.json" <<'PY'
import json, sys
try: print(json.load(open(sys.argv[1])).get('id', ''))
except (ValueError, OSError): print('')
PY
)"
if [[ -n "$SUBMISSION_ID" ]]; then
  xcrun notarytool log "$SUBMISSION_ID" "${NOTARY_ARGS[@]}" "$REPORT_DIR/apple-log.json" || true
fi
if [[ "$SUBMIT_EXIT" -ne 0 ]] || ! python3 - "$REPORT_DIR/submission.json" <<'PY'
import json, sys
try: sys.exit(0 if json.load(open(sys.argv[1])).get('status') == 'Accepted' else 1)
except (ValueError, OSError): sys.exit(1)
PY
then
  echo "Apple did not confirm Accepted. No new distribution files were written. Inspect $REPORT_DIR; if processing is still in progress, check submission $SUBMISSION_ID before retrying." >&2
  exit 1
fi
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --strict "$APP"
spctl --assess --type execute --verbose "$APP"
ARCHIVE="ConstellationBar-$(cat VERSION)-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGING_DIR/$ARCHIVE"
(cd "$STAGING_DIR" && shasum -a 256 "$ARCHIVE" > SHA256SUMS)
mkdir -p .build/distribution
mv "$STAGING_DIR/$ARCHIVE" .build/distribution/
mv "$STAGING_DIR/SHA256SUMS" .build/distribution/
echo "$PROJECT_ROOT/.build/distribution/$ARCHIVE"
echo "Apple notarization record: $REPORT_DIR"
