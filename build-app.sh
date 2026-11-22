#!/usr/bin/env bash
set -euo pipefail

APP_NAME="KeyClack"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

INSTALL_FLAG=false
UNIVERSAL_FLAG=false
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL_FLAG=true ;;
    --universal) UNIVERSAL_FLAG=true ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: build-app.sh must be run on macOS (detected $(uname -s))."
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "Error: Swift toolchain not found. Install Apple Command Line Tools with:"
  echo "  xcode-select --install"
  exit 1
fi

cd "$SCRIPT_DIR"
if [[ "$UNIVERSAL_FLAG" == "true" ]]; then
  echo "==> Building $APP_NAME (universal release: arm64 + x86_64)..."
  swift build -c release --arch arm64 --arch x86_64
  BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"
else
  echo "==> Building $APP_NAME (release)..."
  swift build -c release
  BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
fi

if [[ ! -f "$BIN_PATH" ]]; then
  echo "Error: compiled binary not found at $BIN_PATH"
  exit 1
fi

echo "==> Packaging $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
cp "$SCRIPT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

# Generate AppIcon.icns from Resources/AppIcon.svg using built-in macOS tools (qlmanage/sips/iconutil)
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

PNG_1024="$BUILD_DIR/icon_1024.png"
if command -v rsvg-convert >/dev/null 2>&1; then
  rsvg-convert -w 1024 -h 1024 "$SCRIPT_DIR/Resources/AppIcon.svg" -o "$PNG_1024"
elif command -v qlmanage >/dev/null 2>&1; then
  qlmanage -t -s 1024 -o "$BUILD_DIR" "$SCRIPT_DIR/Resources/AppIcon.svg" >/dev/null 2>&1 || true
  if [[ -f "$BUILD_DIR/AppIcon.svg.png" ]]; then
    mv "$BUILD_DIR/AppIcon.svg.png" "$PNG_1024"
  fi
fi

if [[ -f "$PNG_1024" ]] && command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$PNG_1024" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null 2>&1
    double=$((size * 2))
    sips -z "$double" "$double" "$PNG_1024" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null 2>&1
  done
  iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns" >/dev/null 2>&1 || true
  rm -rf "$ICONSET_DIR" "$PNG_1024"
fi

# Ad-hoc code sign with a stable designated requirement so macOS Input Monitoring permission persists across rebuilds
echo "==> Signing $APP_NAME.app (ad-hoc)..."
codesign --force --deep --sign - --identifier "com.keyclack.app" "$APP_BUNDLE"

echo ""
echo "✅ Built: $APP_BUNDLE"

if [[ "$INSTALL_FLAG" == "true" ]]; then
  echo "==> Installing to /Applications/$APP_NAME.app..."
  WAS_INSTALLED=false
  if [[ -d "/Applications/$APP_NAME.app" ]]; then
    WAS_INSTALLED=true
  fi
  killall "$APP_NAME" >/dev/null 2>&1 || true
  sleep 0.4
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
  if [[ "$WAS_INSTALLED" == "true" ]]; then
    # Clear stale ad-hoc CDHash from Input Monitoring so macOS won't silently block the rebuilt binary
    tccutil reset ListenEvent com.keyclack.app >/dev/null 2>&1 || true
    echo "ℹ️  Updated existing app — please re-enable KeyClack once in System Settings → Privacy & Security → Input Monitoring."
  fi
  echo "✅ Installed to /Applications/$APP_NAME.app"
  echo "==> Launching $APP_NAME..."
  open "/Applications/$APP_NAME.app"
else
  echo "To install to /Applications and launch:"
  echo "  ./build-app.sh --install"
  echo "Or launch directly:"
  echo "  open \"$APP_BUNDLE\""
fi
