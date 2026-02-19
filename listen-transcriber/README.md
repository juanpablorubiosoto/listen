# Listen Transcriber (macOS Intel)

App local para grabar salida del sistema vía BlackHole y transcribir offline con whisper.cpp.

## Requisitos
- BlackHole 2ch instalado en macOS.
- Xcode Command Line Tools (para compilar whisper.cpp con `make`/`cmake`).

## Pasos
1) Configura BlackHole
- En Audio MIDI Setup crea un **Multi-Output Device** con tus speakers + BlackHole 2ch.
- Selecciona ese dispositivo como salida del sistema o de Zoom/Meet.

2) Obtener binarios (ffmpeg + whisper-cli)
```bash
./scripts/fetch_binaries.sh
```
El script usa el zip de ffmpeg para macOS Intel desde martin-riedl (listado en ffmpeg.org).

3) Construir app
```bash
./scripts/build_app.sh
```

4) Ejecutar
Abre `build/ListenTranscriber.app`.

## Uso rápido
- Botón **Detectar BlackHole 2ch** para obtener el índice.
- **Iniciar grabación** para capturar audio.
- **Transcribir** para generar el `.txt`.

## Salidas
- Audio: `~/Downloads/Transcripts/meeting-<timestamp>.wav`
- Texto: `~/Downloads/Transcripts/meeting-<timestamp>-transcript.txt`

## Modelos
El botón **Descargar modelo** baja los modelos oficiales `ggml-small.bin` o `ggml-medium.bin`.
