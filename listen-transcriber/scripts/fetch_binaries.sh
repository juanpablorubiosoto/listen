#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$ROOT/bin"
TMP_DIR="$(mktemp -d)"

mkdir -p "$BIN_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

printf "\n[1/2] Descargando ffmpeg (Intel) desde martin-riedl.de...\n"
FFMPEG_ZIP="$TMP_DIR/ffmpeg.zip"
curl -LJ --fail --retry 3 --retry-delay 2 "https://ffmpeg.martin-riedl.de/redirect/latest/macos/amd64/release/ffmpeg.zip" -o "$FFMPEG_ZIP"
if ! unzip -tq "$FFMPEG_ZIP" >/dev/null 2>&1; then
  echo "El zip descargado no es válido. Reintenta (la URL debe devolver un zip)." >&2
  exit 1
fi
unzip -q "$FFMPEG_ZIP" -d "$TMP_DIR/ffmpeg"
if [[ -f "$TMP_DIR/ffmpeg/ffmpeg" ]]; then
  mv "$TMP_DIR/ffmpeg/ffmpeg" "$BIN_DIR/ffmpeg"
  chmod +x "$BIN_DIR/ffmpeg"
else
  echo "No encontré el binario ffmpeg dentro del zip." >&2
  exit 1
fi

printf "\n[2/2] Descargando y compilando whisper.cpp (whisper-cli)...\n"
WHISPER_DIR="$TMP_DIR/whisper.cpp"
git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git "$WHISPER_DIR"
pushd "$WHISPER_DIR" >/dev/null

if command -v cmake >/dev/null; then
  cmake -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DGGML_BUILD_SHARED=OFF -DWHISPER_BUILD_SHARED=OFF
  cmake --build build -j
  if [[ -f build/bin/whisper-cli ]]; then
    cp build/bin/whisper-cli "$BIN_DIR/whisper-cli"
  elif [[ -f build/bin/main ]]; then
    cp build/bin/main "$BIN_DIR/whisper-cli"
  else
    echo "No encontré whisper-cli ni main en build/bin" >&2
    exit 1
  fi
else
  make -j
  if [[ -f whisper-cli ]]; then
    cp whisper-cli "$BIN_DIR/whisper-cli"
  elif [[ -f main ]]; then
    cp main "$BIN_DIR/whisper-cli"
  else
    echo "No encontré whisper-cli ni main en el build" >&2
    exit 1
  fi
fi

chmod +x "$BIN_DIR/whisper-cli"

# Copia dylibs si se generaron y agrega rpath para que el binario los encuentre
find build -maxdepth 6 -name "*.dylib" -print0 2>/dev/null | while IFS= read -r -d '' lib; do
  cp "$lib" "$BIN_DIR/"
done
if command -v install_name_tool >/dev/null; then
  install_name_tool -add_rpath "@loader_path" "$BIN_DIR/whisper-cli" || true
fi

popd >/dev/null
printf "\nListo. Binarios en: %s\n" "$BIN_DIR"
