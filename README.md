# Glideslope

Glideslope is a tiny macOS menu bar gauge for Codex usage pressure.

The menu bar icon has two hands:

- long hand: 5-hour usage window
- short hand: weekly usage window

The hands are pace-relative consumption meters. A hand pegged left means `0%` consumed, centered means exactly on the expected reset pace, and pegged right means `100%` consumed / `0%` remaining.

The hand color follows system appearance: black in light mode, white in dark mode.

The menu uses a simple pressure color:

- blue: high / too cold / plenty of slack
- green: good / on pace
- red: low / too hot / usage is ahead of pace

The native app reads local Codex auth from `~/.codex/auth.json`, calls the ChatGPT usage endpoint used by Codex, and computes whether each window is ahead of or behind its expected reset pace. It never prints or stores the auth token.

## Requirements

- macOS 14+
- Swift toolchain / Command Line Tools for local builds

No Apple Developer account is required for local unsigned builds. A Developer ID account is only needed later for a polished signed and notarized public DMG.

## Run the Native App

```sh
git clone https://github.com/owl-and-kestrel/glideslope.git
cd glideslope
./script/build_and_run.sh
```

The script builds a local unsigned app bundle at:

```text
dist/Glideslope.app
```

## CLI

The original Node CLI remains useful for tests, scripting, and debugging:

```sh
node ./bin/glideslope.mjs status --json
node ./bin/glideslope.mjs swiftbar
```

## Optional SwiftBar Renderer

SwiftBar is no longer the recommended default. If you already use SwiftBar and want a text renderer, point SwiftBar at `swiftbar/glideslope.1m.sh` or run:

```sh
./scripts/install-swiftbar.sh
```

## Fallback

If the private backend endpoint fails, the CLI renders cached state. You can also seed manual values:

```sh
node ./bin/glideslope.mjs manual \
  --primary-used 20 \
  --primary-reset-at 1779030000 \
  --weekly-used 6 \
  --weekly-reset-at 1779548400
```

CLI fallback state is stored at:

```text
~/.codex-usage-pressure/state.json
```

## Development

```sh
npm test
swift build
./script/build_and_run.sh --verify
```

## License

MIT
