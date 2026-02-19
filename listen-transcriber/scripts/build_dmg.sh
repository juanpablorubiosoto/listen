#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ListenTranscriber"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
STAGING="$BUILD_DIR/dmg"
DMG_PATH="$BUILD_DIR/ListenTranscriber.dmg"
BLACKHOLE_PKG="$ROOT/Resources/BlackHole2ch.pkg"
LICENSES_DIR="$ROOT/../LICENSES"
THIRD_PARTY="$ROOT/../THIRD_PARTY_NOTICES.md"
NOTICE_FILE="$ROOT/../NOTICE"

"$ROOT/scripts/build_app.sh"

rm -rf "$STAGING"
mkdir -p "$STAGING"

if [[ ! -d "$APP_DIR" ]]; then
  echo "No encontré la app en $APP_DIR" >&2
  exit 1
fi

cp -R "$APP_DIR" "$STAGING/"

if [[ -f "$BLACKHOLE_PKG" ]]; then
  cp "$BLACKHOLE_PKG" "$STAGING/BlackHole2ch.pkg"
fi

if [[ -d "$LICENSES_DIR" ]]; then
  cp -R "$LICENSES_DIR" "$STAGING/"
fi
if [[ -f "$THIRD_PARTY" ]]; then
  cp "$THIRD_PARTY" "$STAGING/THIRD_PARTY_NOTICES.md"
fi
if [[ -f "$NOTICE_FILE" ]]; then
  cp "$NOTICE_FILE" "$STAGING/NOTICE"
fi

cat > "$STAGING/README.txt" <<'EOF'
Listen Transcriber (offline)

1) Instala BlackHole 2ch
   - Abre BlackHole2ch.pkg y sigue el instalador.

2) Abre ListenTranscriber.app
   - Da permisos de Micrófono y Grabación de Pantalla.

3) Configura Audio MIDI Setup
   - Crea un Multi‑Output Device: Built‑in Output + BlackHole 2ch.
   - (Opcional) Aggregate Device: Built‑in Mic + BlackHole 2ch.

Notas:
 - La app no puede crear estos dispositivos automáticamente por seguridad de macOS.
 - El modelo de Whisper se descarga la primera vez desde Settings.
 - BlackHole es GPLv3. Fuente: https://github.com/ExistentialAudio/BlackHole
EOF

hdiutil create -volname "ListenTranscriber" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"
echo "DMG listo en: $DMG_PATH"
