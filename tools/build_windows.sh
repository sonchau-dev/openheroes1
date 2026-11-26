#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

GODOT="${GODOT:-$(which godot 2>/dev/null || echo "$HOME/Applications/godot")}"

if [ ! -x "$GODOT" ]; then
    echo "Error: Godot executable not found at '$GODOT'. Please set \$GODOT." >&2
    exit 1
fi

BUILD_DIR="$ROOT_DIR/build/homm1-windows"
echo "==> Building HOMM1 Godot for Windows (x86_64)..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Exporting Windows Desktop release..."
"$GODOT" --headless --path "$ROOT_DIR" --export-release "Windows Desktop" "$BUILD_DIR/homm1.exe"

echo "==> Packaging zip archive..."
rm -f "$ROOT_DIR/build/homm1-windows.zip"
(cd "$ROOT_DIR/build" && zip -r -q "homm1-windows.zip" homm1-windows)

echo ""
echo "=========================================================="
echo "✅ Windows build complete!"
echo "Folder:  $BUILD_DIR"
echo "Archive: $ROOT_DIR/build/homm1-windows.zip"
echo "=========================================================="
