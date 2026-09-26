#!/usr/bin/env bash
# Verified development build. Plain `swift build` remains a compiler-only command.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
xcrun swift build
BINARY_DIR="$(xcrun swift build --show-bin-path)"
./scripts/verify-ui.sh "$BINARY_DIR/ConstellationBar"
