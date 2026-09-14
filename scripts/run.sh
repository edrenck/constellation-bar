#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
xcrun swift build
BINARY_DIR="$(xcrun swift build --show-bin-path)"
exec "$BINARY_DIR/ConstellationBar" "$@"
