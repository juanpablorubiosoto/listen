#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ListenTranscriber"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
BIN_DIR="$ROOT/bin"
SRC="$ROOT/Sources/App.swift"
INFO_PLIST="$ROOT/Resources/Info.plist"
APP_ICON_PNG="$ROOT/Resources/AppIcon.png"
BLACKHOLE_PKG="$ROOT/Resources/BlackHole2ch.pkg"

mkdir -p "$MACOS_DIR" "$RES_DIR/bin"

SDK_PATH="$(xcrun --show-sdk-path)"

xcrun swiftc -O \
  -sdk "$SDK_PATH" \
  -target x86_64-apple-macos13.0 \
  -parse-as-library \
  -framework SwiftUI \
  -framework AppKit \
  -framework Foundation \
  -o "$MACOS_DIR/$APP_NAME" \
  "$SRC"

cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"

if [[ -f "$APP_ICON_PNG" ]]; then
  ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
  ICON_ICNS="$BUILD_DIR/AppIcon.icns"
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16   "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32   "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32   "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64   "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"
  cp "$ICON_ICNS" "$RES_DIR/AppIcon.icns"
fi

if [[ -f "$BLACKHOLE_PKG" ]]; then
  cp "$BLACKHOLE_PKG" "$RES_DIR/BlackHole2ch.pkg"
fi

if [[ -f "$BIN_DIR/ffmpeg" ]]; then
  cp "$BIN_DIR/ffmpeg" "$RES_DIR/bin/ffmpeg"
  chmod +x "$RES_DIR/bin/ffmpeg"
else
  echo "Falta $BIN_DIR/ffmpeg. Corre scripts/fetch_binaries.sh" >&2
  exit 1
fi

if [[ -f "$BIN_DIR/whisper-cli" ]]; then
  cp "$BIN_DIR/whisper-cli" "$RES_DIR/bin/whisper-cli"
  chmod +x "$RES_DIR/bin/whisper-cli"
  if command -v install_name_tool >/dev/null; then
    if ! otool -l "$RES_DIR/bin/whisper-cli" | grep -q "@loader_path"; then
      install_name_tool -add_rpath "@loader_path" "$RES_DIR/bin/whisper-cli" || true
    fi
  fi
else
  echo "Falta $BIN_DIR/whisper-cli. Corre scripts/fetch_binaries.sh" >&2
  exit 1
fi

if ls "$BIN_DIR"/*.dylib >/dev/null 2>&1; then
  cp "$BIN_DIR"/*.dylib "$RES_DIR/bin/"
fi

echo "\nApp lista en: $APP_DIR"
