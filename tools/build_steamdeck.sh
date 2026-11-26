#!/usr/bin/env bash
set -euo pipefail

# Resolve project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

GODOT="${GODOT:-$(which godot 2>/dev/null || echo "$HOME/Applications/godot")}"

if [ ! -x "$GODOT" ]; then
    echo "Error: Godot executable not found at '$GODOT'. Please set \$GODOT." >&2
    exit 1
fi

BUILD_DIR="$ROOT_DIR/build/homm1-steamdeck"
echo "==> Building HOMM1 Godot for Steam Deck (Linux x86_64)..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Exporting project pack (PCK)..."
"$GODOT" --headless --path "$ROOT_DIR" --export-pack "Linux/X11" "$BUILD_DIR/homm1.pck"

echo "==> Copying runner binary..."
REAL_GODOT="$(readlink -f "$GODOT")"
cp "$REAL_GODOT" "$BUILD_DIR/homm1.x86_64"
chmod +x "$BUILD_DIR/homm1.x86_64"

echo "==> Writing launch script..."
cat << 'EOF' > "$BUILD_DIR/start.sh"
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
exec ./homm1.x86_64 "$@"
EOF
chmod +x "$BUILD_DIR/start.sh"

echo "==> Packaging archive for easy transfer..."
tar -czf "$ROOT_DIR/build/homm1-steamdeck.tar.gz" -C "$ROOT_DIR/build" homm1-steamdeck

echo ""
echo "=========================================================="
echo "✅ Steam Deck build complete!"
echo "Folder:  $BUILD_DIR"
echo "Archive: $ROOT_DIR/build/homm1-steamdeck.tar.gz"
echo "=========================================================="
