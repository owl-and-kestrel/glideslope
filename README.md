# Glideslope

Glideslope is a tiny macOS menu bar gauge for **Codex and Claude Code** usage pressure.

The dial is a dark circle with a dotted gauge scale and up to four hands, drawn as bold lines in **separate radial bands** (so they never swallow each other when their angles align): the long (weekly) window is a long line from the hub out past the tick marks, and the short (~5h) window is a short line in the outer band crossing the ticks (an emphasized tick). They are vivid against the dark face (with only a thin dark edge for separation) — the most dominant element. The scale recedes to small white dots; the only colored part of the scale is a **solid pure-red (`#FF0000`) redline arc on the hot end** — the side that actually matters.

Hands are deconflicted on three axes:

- **provider → color:** Codex is teal, Claude is coral.
- **window → length:** the fast (~5h) window is a long hand; the slow (weekly) window is a short hand.
- **pressure → depth:** the most-constrained (highest-pressure) window draws on top, so the hand that matters most is in the foreground.

So a long teal hand is Codex's 5-hour window; a short coral hand is Claude's weekly window, and so on.

The hands are pace-relative consumption meters. A hand pegged left means `0%` consumed, centered means exactly on the expected reset pace, and pegged right means `100%` consumed / `0%` remaining.

When a provider isn't signed in (or its token has expired), the dropdown shows a **Sign in to …** item that launches that CLI's login flow in Terminal (`codex login` / `claude auth login`); after signing in, hit Refresh.

The menu groups windows by provider and uses a simple pressure color per window:

- blue: high / too cold / plenty of slack
- green: good / on pace
- red: low / too hot / usage is ahead of pace

The native app:

- reads local Codex auth from `~/.codex/auth.json` and calls the ChatGPT usage endpoint Codex uses;
- gets a Claude Code OAuth token and calls Anthropic's subscription usage endpoint (`/api/oauth/usage`), mapping the `five_hour` / `seven_day` windows onto the fast/slow hands.

It never prints or stores either token. Each provider is polled independently, so one being unavailable never blocks the other — an unavailable provider simply drops its hands and explains why in the dropdown.

### Claude Code credential

The reader is **read-only** and never writes to the Keychain (writing back a rotated token via the `security` CLI can reset the item's ACL and lock Claude Code out of its own credential — so we don't). The token is resolved in precedence order:

1. **`CLAUDE_CODE_OAUTH_TOKEN`** env var.
2. **Token file** — `~/.glideslope/claude-token` (override with `GLIDESLOPE_CLAUDE_TOKEN_FILE`). First non-comment line. This is the reliable channel for a menu-bar/login-item app, which does not inherit your shell environment.
3. **Keychain** (macOS) — shell out to the trusted `security` binary for the `Claude Code-credentials` item (mirrors Astra's `providers/cli.py`). An unsigned app reading it directly via the Security framework fails the ACL check, so the `security` route is what works. macOS may ask permission — choose *Always Allow*.

For an **always-live** Claude hand without keychain risk, mint a long-lived token and drop it in the file:

```sh
claude setup-token
mkdir -p ~/.glideslope
printf '%s\n' '<token>' > ~/.glideslope/claude-token
chmod 600 ~/.glideslope/claude-token
```

When relying only on the Keychain, an expired access token degrades to `token expired — open Claude Code to refresh` until Claude Code renews it. The usage URL can be overridden with `GLIDESLOPE_CLAUDE_USAGE_URL`.

> Auto-refresh of the Claude token (so the hand stays live without re-opening Claude Code) is a deliberate follow-up — it requires writing the rotated credential back to the shared Keychain item, which we want to validate carefully before shipping.

### Preview

`Glideslope --render preview.png` rasterizes the dial across a few usage scenarios on both light and dark backgrounds — handy for tuning the hands without watching the live menu bar.

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
