import Foundation
import Observation

@Observable
final class UsageStore {
  private let codex = CodexUsageClient()
  private let claude = ClaudeUsageClient()

  var status = UsageStatus()

  /// Last successful windows per provider. A transient fetch failure (e.g. an
  /// HTTP 429 on Claude's usage endpoint) should never blank the hands, so we
  /// keep showing the most recent good reading, labeled stale.
  private var lastGood: [Provider: [UsageWindow]] = [:]

  // Claude's usage endpoint rate-limits aggressively (it's meant for on-demand
  // `/usage` lookups, not a 60s poll), so we poll it gently and back off hard
  // on failure, decoupled from Codex's per-minute cadence.
  private static let claudeBaseInterval: TimeInterval = 240
  private static let claudeMaxBackoff: TimeInterval = 900
  private var claudeNextAllowed: Date = .distantPast
  private var claudeBackoff: TimeInterval = 0

  @MainActor
  func refresh() async {
    let now = Date()
    // Codex polls every cycle; copy the (Sendable) client into a local so we
    // don't send main-actor `self` across the concurrency boundary.
    let codex = self.codex
    async let codexResult = codex.result(now: now)

    // Poll Claude only when its gentle cadence/backoff allows.
    let claudeResult: ProviderResult
    if now >= claudeNextAllowed {
      let fresh = await claude.result(now: now)
      if fresh.ok {
        claudeBackoff = 0
        claudeNextAllowed = now.addingTimeInterval(Self.claudeBaseInterval)
      } else {
        claudeBackoff = claudeBackoff == 0
          ? Self.claudeBaseInterval
          : min(Self.claudeMaxBackoff, claudeBackoff * 2)
        claudeNextAllowed = now.addingTimeInterval(claudeBackoff)
      }
      claudeResult = fresh
    } else {
      // Not due yet — let reconcile() fall back to the cached hands.
      claudeResult = .failure(.claude, source: "throttled", error: "rate-limited — retrying")
    }

    status = UsageStatus(
      generatedAt: now,
      results: [reconcile(await codexResult), reconcile(claudeResult)]
    )
  }

  /// Fold a fresh poll against the last-good cache: on success, refresh the
  /// cache; on a transient failure, fall back to the cached windows so the
  /// hands stay on screen (marked `cached`) rather than vanishing.
  private func reconcile(_ result: ProviderResult) -> ProviderResult {
    if result.ok, !result.windows.isEmpty {
      lastGood[result.provider] = result.windows
      return result
    }
    if let cached = lastGood[result.provider], !cached.isEmpty {
      return ProviderResult(
        provider: result.provider,
        ok: true,
        source: "cached",
        error: result.error,
        windows: cached
      )
    }
    return result
  }

  @MainActor
  func runRefreshLoop() async {
    await refresh()

    while !Task.isCancelled {
      try? await Task.sleep(for: .seconds(60))
      await refresh()
    }
  }
}
