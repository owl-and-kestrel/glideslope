# Visual and credential contract acceptance — 2026-08-02

Scope: local, non-secret acceptance of Glideslope's advertised dial semantics and
Claude Code credential precedence. No real credential, network usage endpoint,
Keychain item, release feed, or installed application state was read or changed.

## Credential resolution

The production resolver now accepts read-only dependencies at a pure test seam;
the live client still calls that same resolver. The seam has no operation capable
of writing, rotating, or refreshing credentials.

`swift test` passed 20 tests in five suites, including five new credential tests:

- `CLAUDE_CODE_OAUTH_TOKEN` wins without reading the file or Keychain;
- the configured token file wins without reading the Keychain;
- the default file path is derived as `~/.glideslope/claude-token`;
- the Keychain JSON fallback trims the token and preserves millisecond expiry;
- a malformed or empty Keychain credential fails closed.

The fixtures use only conspicuous strings such as `environment-token` and paths
under `/nonsecret`; they never invoke `/usr/bin/security`.

## Renderer acceptance

Command:

```sh
swift run Glideslope --render /tmp/glideslope-contract-VArNra/glideslope-preview.png
```

Generated artifact:

- format: 16-bit RGBA PNG, non-interlaced;
- dimensions: 3392 by 1240 pixels;
- size: 314,920 bytes;
- SHA-256: `839121bc73a0081594abdba718553a34f2d2607e1945e1b44899bdd2f1885561`.

The rendered twelve-scenario sheet was inspected at original resolution. It
demonstrates both light and dark backgrounds and the advertised typical,
Codex-only, Claude-only, Fable-scoped, aligned-reset, and pegged states.
Provider color, fast/slow hand length and radial-band separation, scoped-limit
star, reset clock, tick tracks, pure-red hot arc, and pressure ordering remain
visually distinguishable. Overlapping provider hands remain independently
legible. Long hands intentionally extend to the icon canvas boundary, consistent
with the documented permissive radius/clipping behavior.

## Limits

This receipt accepts deterministic source and renderer semantics. It does not
claim menu interaction, update installation, notarization, live provider usage,
or release-ledger/Chirp publication acceptance.
