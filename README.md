# Listen Transcriber (macOS Intel)

![Platform](https://img.shields.io/badge/platform-macOS%20Intel-lightgrey)
![License](https://img.shields.io/badge/license-Non--Commercial-orange)
![Donate](https://img.shields.io/badge/Donate-PayPal-blue)

App local para grabar la salida del sistema con BlackHole y transcribir offline con whisper.cpp. Incluye modo **menubar**, wizard de setup y build de **DMG**.

English version: see `README.en.md`.

## Donar
PayPal: https://www.paypal.com/donate/?hosted_button_id=4MGT8CYJ4BJZG

## Requisitos
- macOS Intel.
- BlackHole 2ch instalado.
- Xcode Command Line Tools (para compilar whisper.cpp con `make`/`cmake`).

## Setup rápido
1) Instala BlackHole 2ch.
2) En **Audio MIDI Setup** crea:
   - **Multi‑Output Device**: Built‑in Output + BlackHole 2ch.
   - **Aggregate Device** (opcional): Built‑in Mic + BlackHole 2ch.
3) Abre la app y otorga permisos de micrófono y grabación de pantalla.

## Build
1) Obtener binarios (ffmpeg + whisper‑cli):
```bash
./scripts/fetch_binaries.sh
```

2) Construir app:
```bash
./scripts/build_app.sh
```

3) Ejecutar:
Abre `build/ListenTranscriber.app`.

## Menubar
La app crea un icono en la barra superior:
- Start/Stop
- Idioma
- Toggle micrófono
- Abrir ventana

## Setup Wizard
En **Settings → Setup Wizard**:
- Verifica BlackHole 2ch
- Abre Audio MIDI Setup
- Verifica permisos

## DMG
Para generar un DMG:
```bash
./scripts/build_dmg.sh
```
Incluye la app, `BlackHole2ch.pkg` y un README de instalación.

Para incluir el `.pkg` dentro del DMG, coloca el archivo en:
```
Resources/BlackHole2ch.pkg
```

## Uso rápido
- **Detectar BlackHole 2ch** para encontrar el índice.
- **Iniciar grabación** para capturar audio.
- **Transcribir** para generar el `.txt`.
- **Elegir audio** para transcribir un WAV existente.

## Salidas
- Audio: `~/Downloads/Transcripts/<nombre>-<timestamp>.wav`
- Texto: `~/Downloads/Transcripts/<nombre>-<timestamp>-transcript.txt`

## Modelos
El botón **Descargar modelo** baja `ggml-small.bin` o `ggml-medium.bin`.

## Aviso legal
- Licencia: uso **no comercial**. Para uso comercial, escribe a outreach@lsconsulting-co.com.
- BlackHole es de Existential Audio. Este repo no distribuye su instalador por defecto.
