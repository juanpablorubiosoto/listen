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
