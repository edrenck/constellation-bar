#!/usr/bin/env bash
# Run in your own terminal: the password is entered into notarytool's secure prompt.
set -euo pipefail
PROFILE="${CONSTELLATION_NOTARY_PROFILE:-constellation-release}"
printf 'Apple Developer account email: '
read -r APPLE_ACCOUNT
DETECTED_TEAMS="$(security find-identity -v -p codesigning | sed -n 's/.*Developer ID Application: .* (\([A-Z0-9]*\))".*/\1/p' | sort -u)"
DEFAULT_TEAM=""
if [[ -n "$DETECTED_TEAMS" && "$DETECTED_TEAMS" != *$'\n'* ]]; then DEFAULT_TEAM="$DETECTED_TEAMS"; fi
printf 'Developer Team ID [%s]: ' "$DEFAULT_TEAM"
read -r DEVELOPER_TEAM
DEVELOPER_TEAM="${DEVELOPER_TEAM:-$DEFAULT_TEAM}"
if [[ -z "$APPLE_ACCOUNT" || -z "$DEVELOPER_TEAM" ]]; then
  echo 'Account email and Team ID are required.' >&2
  exit 2
fi
printf '\nEnter an Apple app-specific password at the secure prompt below.\n'
printf 'It will be validated with Apple and saved to your local Keychain, not this repository.\n\n'
xcrun notarytool store-credentials "$PROFILE" --apple-id "$APPLE_ACCOUNT" --team-id "$DEVELOPER_TEAM"
printf '\nProfile saved: %s\n' "$PROFILE"
