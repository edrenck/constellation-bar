#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
BUILD_ARGS=(-c release)
if [[ "${1:-}" == "--universal" ]]; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--universal]" >&2
  exit 2
fi
xcrun swift build "${BUILD_ARGS[@]}"
BINARY_DIR="$(xcrun swift build "${BUILD_ARGS[@]}" --show-bin-path)"
APP_DIR="$PROJECT_ROOT/.build/ConstellationBar.app"
STAGING_DIR="$(mktemp -d "$PROJECT_ROOT/.build/app-staging.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
STAGED_APP="$STAGING_DIR/ConstellationBar.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BINARY_DIR/ConstellationBar" "$STAGED_APP/Contents/MacOS/ConstellationBar"
cp extensions/browser-media/README.md "$STAGED_APP/Contents/Resources/BrowserMedia-README.md"
cp Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
xcrun swift scripts/render-icon.swift "$STAGING_DIR/ConstellationBar.iconset"
iconutil -c icns "$STAGING_DIR/ConstellationBar.iconset" -o "$STAGED_APP/Contents/Resources/ConstellationBar.icns"
APP_VERSION="$(cat VERSION)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$STAGED_APP/Contents/Info.plist"
# Personal configurations are never included in a distributable bundle.
SIGNING_IDENTITY="${CONSTELLATION_SIGNING_IDENTITY:--}"
SIGN_ARGS=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  SIGN_ARGS+=(--options runtime --timestamp --entitlements "$PROJECT_ROOT/Resources/ConstellationBar.entitlements")
fi
codesign "${SIGN_ARGS[@]}" "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"
# Preserve the last build until a complete replacement is available.
if [[ -d "$APP_DIR" ]]; then
  rm -rf "$PROJECT_ROOT/.build/ConstellationBar.previous.app"
  mv "$APP_DIR" "$PROJECT_ROOT/.build/ConstellationBar.previous.app"
fi
mv "$STAGED_APP" "$APP_DIR"
echo "$APP_DIR"
