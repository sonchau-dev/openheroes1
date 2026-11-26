#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

GODOT="${GODOT:-$(which godot 2>/dev/null || echo "/Applications/Godot.app/Contents/MacOS/Godot")}"

if [ ! -x "$GODOT" ]; then
    echo "Error: Godot executable not found at '$GODOT'. Please set \$GODOT." >&2
    exit 1
fi

BUILD_DIR="$ROOT_DIR/build/homm1-macos"
echo "==> Building HOMM1 Godot for macOS..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Exporting macOS release..."
"$GODOT" --headless --path "$ROOT_DIR" --export-release "macOS" "$BUILD_DIR/homm1.zip"

echo ""
echo "=========================================================="
echo "✅ macOS build complete!"
echo "Archive: $BUILD_DIR/homm1.zip"
echo "=========================================================="
