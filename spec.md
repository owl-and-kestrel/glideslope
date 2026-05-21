# Glideslope Spec

Glideslope is a tiny macOS menu bar gauge for Codex usage-window pressure.

## Purpose

Codex exposes usage remaining, but the signal is buried and raw percentages are hard to interpret. Glideslope turns the current usage window into a pace reading: whether remaining usage is lower than, equal to, or higher than expected for this point in the window.

The goal is one calm glance, not another dashboard.

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

The menu bar should show the most constrained window: the window with the lowest pressure.

The native icon should use a pace-relative consumption scale. A hand pegged left means `0%` consumed, centered means exactly on the expected reset pace, and pegged right means `100%` consumed / `0%` remaining. In other words, usage from `0%` consumed to the on-track amount maps across the left half, and usage from on-track to exhausted maps across the right half. The hand should resolve to black in light mode and white in dark mode.

Example:

```text
Glideslope +2 even
```

The dropdown should show each tracked window:

```text
5h: 98% left, +4 even
Weekly: 94% left, +2 even
```

Percentages are shown as percentage points of pressure unless otherwise labeled.

## Data Sources

Primary source:

- Read Codex auth from `~/.codex/auth.json`
- Call `https://chatgpt.com/backend-api/wham/usage`
- Use `rate_limit.primary_window` and `rate_limit.secondary_window`
- Expected fields: `used_percent`, `reset_at`, `limit_window_seconds`

Fallback sources:

- Cached last-good response at `~/.codex-usage-pressure/state.json`
- Manual state written by the local CLI

The primary source is intentionally automatic. Manual input exists only as a resilience path.

## Safety

- Never print or cache the auth token.
- Cache only usage payloads and derived status.
- Treat endpoint failures as degraded telemetry, not as zero usage.
- Prefer stale-but-labeled data over a scary blank state.

## Non-Goals

- No in-Codex UI injection.
- No OCR or settings-screen scraping as the normal path.
- No autonomous usage throttling.
- No account sharing, credential export, or third-party service sync.

## Implementation Shape

- A small CLI computes status and writes/reads cache.
- A SwiftBar script renders the CLI output once per minute.
- A future MCP wrapper may expose the same status to Codex, but SwiftBar should not depend on MCP.

## Open Questions

- Should the app name replace `Codex` in the menu bar once installed, e.g. `Glideslope +2 even`?
- Should thresholds be configurable per user?
- Should reset times be displayed as wall-clock time, duration, or both?
