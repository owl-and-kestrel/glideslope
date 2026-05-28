# Glideslope Spec

Glideslope is a tiny macOS menu bar gauge for coding-agent usage-window pressure. It tracks **Codex** and **Claude Code** together.

## Purpose

Both Codex and Claude Code expose usage remaining, but the signal is buried and raw percentages are hard to interpret. Glideslope turns each provider's current usage window into a pace reading: whether remaining usage is lower than, equal to, or higher than expected for this point in the window.

The goal is one calm glance, not another dashboard.

## Providers

Glideslope tracks two providers, each contributing a fast (~5h) and a slow (weekly) window:

- **Codex** — teal hands.
- **Claude Code** — coral hands.

Providers are polled independently; one being unavailable never blocks the other.

## Core Model

For each usage window:

```text
actual_remaining = 1 - used_fraction
expected_remaining = time_until_reset / window_duration
pressure = actual_remaining - expected_remaining
```

Interpretation:

- `low`: remaining usage is below the expected line
- `even`: remaining usage is close to the expected line
- `high`: remaining usage is above the expected line

Default thresholds:

```text
low   pressure < -5 percentage points
even  -5 <= pressure <= +5 percentage points
high  pressure > +5 percentage points
```

## Display

The tooltip/summary names the most constrained window across all providers: the window with the lowest pressure (e.g. `Claude 5h -8% low`).

The native icon is the focus, and the hands are the focus of the icon — the most dominant element. The dial is a dark circle with a fine dotted scale (small white dots) on a square canvas so it never crops; the hands are large and vivid against the dark face. The only colored scale element is a solid bright-red redline arc on the hot end. The hands carry the identity:

- **Provider → hand color.** Codex teal, Claude coral.
- **Window → radial band.** Both hands are bold lines. The long (weekly) window is a long line from a short tail through the hub out past the tick marks; the short (~5h) window is a short line in the outer band, from the edge inward past the ticks (an emphasized tick). The two bands keep the hands from swallowing each other when their angles align.
- **Pressure → depth.** The most-constrained (highest-pressure) window draws last, so the hand that matters most sits in the foreground.
- Each hand has only a thin dark edge (kept minimal so the bright fill dominates).
- The redline marks the consumed-past-pace danger end; a hand swinging into it is the only color cue you need.

Each hand uses a pace-relative consumption scale: pegged left = `0%` consumed, centered = exactly on the expected reset pace, pegged right = `100%` consumed / `0%` remaining. Usage from `0%` to on-track maps across the left half; on-track to exhausted maps across the right half.

When a provider has no data its hands are simply omitted; the gauge degrades to whatever providers are available.

When a provider needs credentials (not signed in, or token expired/rejected), the dropdown surfaces a **Sign in to …** action that launches that CLI's login in Terminal (`codex login` / `claude auth login`).

The dropdown groups windows under each provider:

```text
● Codex
    5h: 98% left, +4 good
    Weekly: 94% left, +2 good
● Claude
    5h: 71% left, -8% low
    Weekly: 88% left, +1 good
```

Percentages are shown as percentage points of pressure unless otherwise labeled.

## Data Sources

### Codex

- Read Codex auth from `~/.codex/auth.json`
- Call `https://chatgpt.com/backend-api/wham/usage`
- Use `rate_limit.primary_window` (fast) and `rate_limit.secondary_window` (slow)
- Expected fields: `used_percent`, `reset_at`, `limit_window_seconds`

- Resolve the OAuth access token in precedence order: (1) `CLAUDE_CODE_OAUTH_TOKEN` env, (2) token file `~/.glideslope/claude-token` (override `GLIDESLOPE_CLAUDE_TOKEN_FILE`) — the reliable channel for a GUI/login-item app that doesn't inherit the shell env, (3) the `Claude Code-credentials` Keychain item via `security find-generic-password -s … -w` (mirrors Astra's `providers/cli.py`; shelling out avoids the ACL failure an unsigned app hits through the Security framework). For an always-live hand, `claude setup-token` mints a long-lived token for the env/file path.
- Call Anthropic's subscription usage endpoint (`https://api.anthropic.com/api/oauth/usage`, overridable via `GLIDESLOPE_CLAUDE_USAGE_URL`) with `Authorization: Bearer …`.
- Map `five_hour` → fast and `seven_day` → slow. Each window carries `utilization` (0–100 percent) and `resets_at` (ISO-8601); the decoder tolerates a few alternate field names but is pinned to this shape.
- **Read-only.** Glideslope never refreshes or rewrites the Keychain item, so it cannot invalidate the refresh token the Claude Code app depends on. An expired access token degrades to `token expired — open Claude Code to refresh`.
- **Gentle polling.** The usage endpoint rate-limits aggressively (it's meant for on-demand `/usage` lookups, not a per-minute poll), so Claude is polled on a slow cadence (~4 min) with exponential backoff on failure, decoupled from Codex's 60s loop. Combined with the last-good cache, a transient `429` keeps the existing hands on screen (labeled `cached`) rather than blanking them.

Fallback sources (Codex):

- Cached last-good response at `~/.codex-usage-pressure/state.json`
- Manual state written by the local CLI

Automatic sources are intentionally primary. Manual input exists only as a resilience path.

## Safety

- Never print or cache any provider auth token.
- Never write back to the Claude Code Keychain item (read-only credential access).
- Cache only usage payloads and derived status.
- Treat endpoint failures as degraded telemetry, not as zero usage.
- Prefer stale-but-labeled data over a scary blank state.

## Non-Goals

- No in-Codex / in-Claude UI injection.
- No OCR or settings-screen scraping as the normal path.
- No autonomous usage throttling.
- No account sharing, credential export, or third-party service sync.

## Implementation Shape

- A small CLI computes status and writes/reads cache.
- A SwiftBar script renders the CLI output once per minute.
- A future MCP wrapper may expose the same status to Codex, but SwiftBar should not depend on MCP.

## Open Questions

- Should thresholds be configurable per user?
- Should reset times be displayed as wall-clock time, duration, or both?
- Decided against Keychain write-back auto-refresh: updating the item via the `security` CLI can reset its ACL and lock Claude Code out of its own credential (this is why Astra stays read-only). The always-live path is instead a long-lived token from `claude setup-token` placed in the env/token-file.
- Validate the Anthropic usage payload field names against a live `200` response and tighten the decoder accordingly (blocked while logged out / no token available).
