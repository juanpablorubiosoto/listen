# Listen Transcriber (macOS Intel)

![Donate](https://img.shields.io/badge/Donate-PayPal-blue)

Local app to record system audio with BlackHole and transcribe offline using whisper.cpp. Includes **menubar mode**, a setup wizard, and **DMG** build.

## Donate
PayPal: https://www.paypal.com/donate/?hosted_button_id=4MGT8CYJ4BJZG

## Requirements
- macOS Intel.
- BlackHole 2ch installed. Official download: https://existential.audio/blackhole/download/
- Xcode Command Line Tools (to build whisper.cpp with `make`/`cmake`).

## Quick Setup
1) Install BlackHole 2ch.
2) In **Audio MIDI Setup**, create:
   - **Multi‑Output Device**: Built‑in Output + BlackHole 2ch.
   - **Aggregate Device** (optional): Built‑in Mic + BlackHole 2ch.
3) Open the app and grant microphone + screen recording permissions.

## Build
1) Fetch binaries (ffmpeg + whisper‑cli):
```bash
./scripts/fetch_binaries.sh
```

2) Build app:
```bash
./scripts/build_app.sh
```

3) Run:
Open `build/ListenTranscriber.app`.

## Menubar
The app adds a menubar icon with:
- Start/Stop
- Language
- Mic toggle
- Open window

## Setup Wizard
In **Settings → Setup Wizard**:
- Checks BlackHole 2ch
- Opens Audio MIDI Setup
- Verifies permissions

## DMG
To build a DMG:
```bash
./scripts/build_dmg.sh
```
Includes the app, `BlackHole2ch.pkg`, licenses, and a README.

To bundle the `.pkg` inside the DMG, put it here:
```
Resources/BlackHole2ch.pkg
```
BlackHole source (GPLv3): https://github.com/ExistentialAudio/BlackHole

## Quick Use
- **Detect BlackHole 2ch** to find device index.
- **Start Recording** to capture audio.
- **Transcribe** to generate `.txt`.
- **Choose audio** to transcribe an existing WAV.

## Outputs
- Audio: `~/Downloads/Transcripts/<name>-<timestamp>.wav`
- Text: `~/Downloads/Transcripts/<name>-<timestamp>-transcript.txt`

## Models
The **Download model** button fetches `ggml-small.bin` or `ggml-medium.bin`.

## Legal
- License: **non‑commercial use only**. For commercial use, contact outreach@lsconsulting-co.com.
- BlackHole is by Existential Audio. If you distribute the `.pkg`, you must comply with GPLv3.
