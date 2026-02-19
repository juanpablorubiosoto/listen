# Contributing

Thanks for your interest in contributing!

## Scope
- Bug fixes, UI improvements, and better setup UX are welcome.
- Keep the app fully offline and dependency‑light.

## Dev setup
```bash
./scripts/fetch_binaries.sh
./scripts/build_app.sh
```

## Guidelines
- Prefer clear UI and minimal steps for non‑technical users.
- Avoid adding heavy dependencies.
- Keep compatibility with macOS Intel.

## Commit style
- Short, descriptive commits.
- Include screenshots for UI changes when possible.

## Releases
- Update `CHANGELOG.md`.
- Build `ListenTranscriber.dmg` via `./scripts/build_dmg.sh`.
