# Glideslope

A tiny SwiftBar-friendly Codex usage pressure gauge for macOS.

Glideslope turns raw Codex usage-window percentages into a pace reading: are you below, on, or above the expected line for this point in the window?

The automatic path reads the local Codex auth token from `~/.codex/auth.json` and calls the same ChatGPT backend usage endpoint used by the Codex app:

```text
https://chatgpt.com/backend-api/wham/usage
```

That endpoint returns `used_percent`, `reset_at`, and `limit_window_seconds` for the primary and secondary usage windows. The gauge computes:

```text
pressure = actual_remaining_fraction - expected_remaining_fraction
```

Positive pressure means surplus, negative pressure means deficit, and near-zero means on track. The script never prints or stores your auth token.

## Requirements

- macOS
- Node.js 20+
- [SwiftBar](https://swiftbar.app/) for the menu bar widget

## Try It

```sh
node ./bin/glideslope.mjs status --json
node ./bin/glideslope.mjs swiftbar
```

## Install

Clone or download this project, then run:

```sh
./scripts/install-swiftbar.sh
```

The installer creates a symlink in `~/Library/Application Support/SwiftBar/Plugins/`. SwiftBar refreshes based on the filename; `.1m.sh` means once per minute.

You can also install the CLI globally from a checkout:

```sh
npm link
glideslope status
```

## Fallback

If the private backend endpoint fails, the script renders cached state. You can also seed manual values:

```sh
node ./bin/glideslope.mjs manual \
  --primary-used 20 \
  --primary-reset-at 1779030000 \
  --weekly-used 6 \
  --weekly-reset-at 1779548400
```

State is stored at:

```text
~/.codex-usage-pressure/state.json
```

The script never prints the auth token.

## Development

```sh
npm test
```

## License

MIT
