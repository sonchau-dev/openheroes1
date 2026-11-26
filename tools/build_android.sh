#!/usr/bin/env bash
# Export the game as an Android APK. The one-time setup is in the platform
# guides under docs/ (sections 5.1 and 5.3).
#
#   tools/build_android.sh              debug APK, build/homm1-debug.apk
#   tools/build_android.sh --release    signed release APK, build/homm1.apk
#   tools/build_android.sh --install    also install on the connected device
#
# Release builds read the keystore from GODOT_ANDROID_KEYSTORE_RELEASE_PATH,
# GODOT_ANDROID_KEYSTORE_RELEASE_USER and GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

RELEASE=0
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --release) RELEASE=1 ;;
        --install) INSTALL=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

die() { echo "Error: $*" >&2; exit 1; }

case "$(uname -s)" in
    Darwin)
        GODOT_DEFAULT="/Applications/Godot.app/Contents/MacOS/Godot"
        GODOT_DATA="$HOME/Library/Application Support/Godot"
        GODOT_CONFIG="$GODOT_DATA"
        SDK_DEFAULT="$HOME/Library/Android/sdk"
        JAVA_DEFAULT="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
        # Homebrew's openjdk@17 is keg-only, so java_home does not list it.
        if [ -z "$JAVA_DEFAULT" ] && command -v brew >/dev/null; then
            JAVA_DEFAULT="$(brew --prefix openjdk@17 2>/dev/null)/libexec/openjdk.jdk/Contents/Home"
        fi
        ;;
    *)
        GODOT_DEFAULT="$HOME/Applications/godot"
        GODOT_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/godot"
        GODOT_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/godot"
        SDK_DEFAULT="$HOME/Android/Sdk"
        JAVA_DEFAULT=""
        for d in /usr/lib/jvm/java-17-openjdk-amd64 "$HOME/.local/jvm/jdk-17" "$HOME/Android/jdk-17"; do
            if [ -x "$d/bin/keytool" ]; then
                JAVA_DEFAULT="$d"
                break
            fi
        done
        ;;
esac

GODOT="${GODOT:-$GODOT_DEFAULT}"
[ -x "$GODOT" ] || die "Godot not found at '$GODOT'. Set \$GODOT."

# "4.7.2.stable.official.ed1daf0bf" -> templates live in "4.7.2.stable".
VERSION="$("$GODOT" --version | awk -F. '{print $1"."$2"."$3"."$4}')"
MINOR="$(echo "$VERSION" | cut -d. -f1-2)"
TEMPLATES="$GODOT_DATA/export_templates/$VERSION"
SETTINGS="$GODOT_CONFIG/editor_settings-$MINOR.tres"

[ -f "$TEMPLATES/android_debug.apk" ] && [ -f "$TEMPLATES/android_release.apk" ] \
    || die "Android export templates missing from '$TEMPLATES'. See section 5.1 of your platform guide in docs/."

JAVA_HOME="${JAVA_HOME:-$JAVA_DEFAULT}"
[ -n "$JAVA_HOME" ] && [ -x "$JAVA_HOME/bin/keytool" ] \
    || die "JDK 17 not found. Set \$JAVA_HOME. See section 5.3 of your platform guide in docs/."
ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$SDK_DEFAULT}}"
[ -x "$ANDROID_HOME/platform-tools/adb" ] && [ -d "$ANDROID_HOME/build-tools" ] \
    || die "Android SDK not found at '$ANDROID_HOME'. Set \$ANDROID_HOME. See section 5.3 of your platform guide in docs/."

[ -d assets/art ] || die "No game data in assets/. Build it first (section 3 of your platform guide in docs/)."

# Godot reads the JDK, SDK and debug keystore from its editor settings, not
# the environment, so write them there.
KEYSTORE="$GODOT_DATA/keystores/debug.keystore"
mkdir -p "$(dirname "$SETTINGS")"
python3 - "$SETTINGS" "$JAVA_HOME" "$ANDROID_HOME" "$KEYSTORE" <<'EOF'
import os, sys
path, java, sdk, keystore = sys.argv[1:]
want = {
    "export/android/java_sdk_path": java,
    "export/android/android_sdk_path": sdk,
    "export/android/debug_keystore": keystore,
    "export/android/debug_keystore_user": "androiddebugkey",
    "export/android/debug_keystore_pass": "android",
}
lines = open(path).read().splitlines() if os.path.exists(path) else [
    '[gd_resource type="EditorSettings" format=3]', "", "[resource]"]
for i, line in enumerate(lines):
    key = line.split(" = ", 1)[0]
    if key in want:
        lines[i] = '%s = "%s"' % (key, want.pop(key))
lines += ['%s = "%s"' % kv for kv in want.items()]
open(path, "w").write("\n".join(lines) + "\n")
EOF

if [ ! -f "$KEYSTORE" ]; then
    echo "==> Creating the debug keystore..."
    mkdir -p "$(dirname "$KEYSTORE")"
    "$JAVA_HOME/bin/keytool" -genkeypair -keyalg RSA -alias androiddebugkey \
        -keypass android -storepass android -keystore "$KEYSTORE" \
        -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12
fi

mkdir -p build
if [ "$RELEASE" = 1 ]; then
    [ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" ] \
        || die "Release builds need GODOT_ANDROID_KEYSTORE_RELEASE_PATH."
    [ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-}" ] \
        || die "Release builds need GODOT_ANDROID_KEYSTORE_RELEASE_USER."
    [ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-}" ] \
        || die "Release builds need GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD."

    RELEASE_KEYSTORE="${GODOT_ANDROID_KEYSTORE_RELEASE_PATH/#\~/$HOME}"
    [ -f "$RELEASE_KEYSTORE" ] \
        || die "Release keystore not found at '$RELEASE_KEYSTORE'."

    CRED_FILE="$ROOT_DIR/.godot/export_credentials.cfg"
    mkdir -p "$(dirname "$CRED_FILE")"
    python3 - "$CRED_FILE" "$RELEASE_KEYSTORE" "$GODOT_ANDROID_KEYSTORE_RELEASE_USER" "$GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD" <<'EOF'
import os, sys, configparser
cred_path, ks_path, ks_user, ks_pass = sys.argv[1:]
cfg = configparser.ConfigParser()
if os.path.exists(cred_path):
    cfg.read(cred_path)
sec = "preset.1.options"
if not cfg.has_section(sec):
    cfg.add_section(sec)
cfg.set(sec, "keystore/release", f'"{ks_path}"')
cfg.set(sec, "keystore/release_user", f'"{ks_user}"')
cfg.set(sec, "keystore/release_password", f'"{ks_pass}"')
with open(cred_path, "w") as f:
    cfg.write(f)
EOF
    cleanup_credentials() {
        if [ -f "$CRED_FILE" ]; then
            python3 - "$CRED_FILE" <<'EOF'
import sys, configparser
cred_path = sys.argv[1]
cfg = configparser.ConfigParser()
cfg.read(cred_path)
if cfg.has_section("preset.1.options"):
    cfg.remove_section("preset.1.options")
with open(cred_path, "w") as f:
    cfg.write(f)
EOF
        fi
    }
    trap cleanup_credentials EXIT

    APK="build/homm1.apk"
    MODE="--export-release"
else
    APK="build/homm1-debug.apk"
    MODE="--export-debug"
fi

echo "==> Exporting $APK..."
rm -f "$APK"
"$GODOT" --headless --path "$ROOT_DIR" "$MODE" "Android" "$ROOT_DIR/$APK"
[ -f "$APK" ] || die "Godot finished without writing $APK. Read the errors above."
echo "==> Wrote $APK ($(du -h "$APK" | cut -f1))"

if [ "$INSTALL" = 1 ]; then
    echo "==> Installing on the connected device..."
    "$ANDROID_HOME/platform-tools/adb" install -r "$APK"
fi
