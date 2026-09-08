#!/usr/bin/env bash
# Double-click in Finder to enter credentials directly in Terminal.
cd "$(dirname "$0")" || exit 1
./setup-notarization.sh
result=$?
printf '\nPress Return to close this setup command. '
read -r
exit "$result"
