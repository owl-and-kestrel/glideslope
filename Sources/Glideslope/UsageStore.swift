import Foundation
import Observation

@Observable
final class UsageStore {
  private let client = CodexUsageClient()

  var status = UsageStatus()

  @MainActor
  func refresh() async {
    status = await client.status()
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

struct CodexUsageClient {
  private let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

  func status() async -> UsageStatus {
    do {
      let payload = try await fetchPayload()
      return status(from: payload, source: "live")
    } catch {
      return UsageStatus(
        ok: false,
        source: "error",
        error: String(describing: error),
        generatedAt: .now,
        windows: []
      )
    }
  }

  private func fetchPayload() async throws -> UsagePayload {
    let auth = try readAuth()
    guard let token = auth.tokens?.accessToken, !token.isEmpty else {
      throw UsageError.missingToken
    }

    var request = URLRequest(url: usageURL)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Glideslope/0.2", forHTTPHeaderField: "User-Agent")
    if let accountId = auth.tokens?.accountId, !accountId.isEmpty {
      request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw UsageError.fetchFailed
    }

    return try JSONDecoder().decode(UsagePayload.self, from: data)
  }

  private func readAuth() throws -> AuthFile {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"].map(URL.init(fileURLWithPath:)) ?? home.appending(path: ".codex")
    let authURL = codexHome.appending(path: "auth.json")
    let data = try Data(contentsOf: authURL)
    return try JSONDecoder().decode(AuthFile.self, from: data)
  }

  private func status(from payload: UsagePayload, source: String) -> UsageStatus {
    let now = Date()
    let windows = [
      normalize(id: "primary_window", label: "5h", window: payload.rateLimit.primaryWindow, now: now),
      normalize(id: "secondary_window", label: "Weekly", window: payload.rateLimit.secondaryWindow, now: now)
    ].compactMap { $0 }

    return UsageStatus(
      ok: !windows.isEmpty,
      source: source,
      error: nil,
      generatedAt: now,
      windows: windows
    )
  }

  private func normalize(id: String, label: String, window: RateLimitWindow?, now: Date) -> UsageWindow? {
    guard let window else {
      return nil
    }

    let used = min(100, max(0, window.usedPercent))
    let resetAt = Date(timeIntervalSince1970: window.resetAt)
    let secondsRemaining = max(0, resetAt.timeIntervalSince(now))
    let duration = max(60, window.limitWindowSeconds)
    let expectedRemaining = min(1, max(0, secondsRemaining / duration))
    let actualRemaining = min(1, max(0, 1 - used / 100))
    let pressure = actualRemaining - expectedRemaining

    return UsageWindow(
      id: id,
      label: label,
      usedPercent: used,
      remainingPercent: actualRemaining * 100,
      expectedRemainingPercent: expectedRemaining * 100,
      pressurePercent: pressure * 100,
      resetAt: resetAt,
      limitWindowSeconds: duration
    )
  }
}

enum UsageError: Error {
  case missingToken
  case fetchFailed
}
