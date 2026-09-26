#!/usr/bin/env bash
# Fail a build if the native journeys or the actual built app cannot complete.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [built-executable]" >&2
  exit 2
fi
if [[ $# -eq 1 ]]; then
  JOURNEY_BINARY="$1"
else
  BINARY_DIR="$(xcrun swift build --show-bin-path)"
  JOURNEY_BINARY="$BINARY_DIR/ConstellationBar"
fi
if [[ ! -x "$JOURNEY_BINARY" ]]; then
  echo "UI verification requires a built executable: $JOURNEY_BINARY" >&2
  exit 2
fi
mkdir -p "$PROJECT_ROOT/.build/ui-journeys"
JOURNEY_ARTIFACTS="$(mktemp -d "$PROJECT_ROOT/.build/ui-journeys/run.XXXXXX")"
export CONSTELLATION_UI_TESTS=1
export CONSTELLATION_REQUIRE_UI_TESTS=1
export CONSTELLATION_UI_TEST_BINARY="$JOURNEY_BINARY"
export CONSTELLATION_UI_TEST_ARTIFACT_DIR="$JOURNEY_ARTIFACTS"
echo "Verifying native UI journeys and app startup. Results: $JOURNEY_ARTIFACTS"
xcrun swift test 2>&1 | tee "$JOURNEY_ARTIFACTS/tests.log"

# AppKit recovers these layouts by discarding constraints even when assertions pass.
# Keep the original test log so the triggering journey remains reviewable.
if grep -Ei 'Conflicting constraints detected|Unable to simultaneously satisfy constraints|Will attempt to recover by breaking' "$JOURNEY_ARTIFACTS/tests.log" >/dev/null; then
  echo "Native UI verification failed: Auto Layout discarded conflicting constraints. See $JOURNEY_ARTIFACTS/tests.log" >&2
  exit 1
fi
