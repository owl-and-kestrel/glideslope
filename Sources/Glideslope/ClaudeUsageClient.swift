import Foundation

/// Reads Claude Code's OAuth access token and polls Anthropic's subscription
/// usage endpoint, mapping the five-hour / seven-day windows onto Glideslope's
/// fast/slow pace windows.
///
/// Token acquisition mirrors Astra's proven `providers/cli.py` path: prefer the
/// `CLAUDE_CODE_OAUTH_TOKEN` env var, then shell out to the trusted `security`
/// binary for the `Claude Code-credentials` Keychain item. (An unsigned app
/// reading that item directly via the Security framework fails the ACL check —
/// shelling out to `security` is what actually works.)
///
/// This client is intentionally **read-only**: it never refreshes or rewrites
/// the Keychain credential, so it can never invalidate the refresh token the
/// Claude Code app itself depends on. When the stored access token has expired
/// it reports a degraded state and waits for Claude Code to refresh it.
struct ClaudeUsageClient: Sendable {
  private static let keychainService = "Claude Code-credentials"
  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.httpAdditionalHeaders = nil
    configuration.httpShouldSetCookies = false
    configuration.httpCookieAcceptPolicy = .never
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 20
    return URLSession(configuration: configuration)
  }()
  private var usageURL: URL {
    let raw = ProcessInfo.processInfo.environment["GLIDESLOPE_CLAUDE_USAGE_URL"]
      ?? "https://api.anthropic.com/api/oauth/usage"
    return URL(string: raw) ?? URL(string: "https://api.anthropic.com/api/oauth/usage")!
  }

  func result(now: Date = Date()) async -> ProviderResult {
    let credential: ClaudeCredential
    do {
      credential = try loadCredential()
    } catch {
      let needsAuth: Bool
      if case ClaudeError.notSignedIn = error { needsAuth = true } else { needsAuth = false }
      return .failure(.claude, source: "error", error: ClaudeUsageClient.describe(error), needsAuth: needsAuth)
    }

    if let expiresAt = credential.expiresAt, expiresAt <= now {
      return .failure(.claude, source: "expired", error: "token expired — sign in to refresh", needsAuth: true)
    }

    do {
      let payload = try await fetchPayload(token: credential.accessToken)
      let windows = ClaudeUsageParser.windows(from: payload, now: now)
      guard ClaudeUsageParser.hasCompleteBroadWindows(windows) else {
        // Do not treat a partial 200 as authoritative. Reconciliation will keep
        // the prior reset-valid snapshot, while a complete later response can
        // still clear scoped limits that are genuinely no longer active.
        return .failure(.claude, source: "error", error: "incomplete usage windows in response")
      }
      return ProviderResult(provider: .claude, ok: true, source: "live", error: nil, windows: windows)
    } catch {
      let needsAuth: Bool
      let retryAfter: TimeInterval?
      if case ClaudeError.fetchFailed(let code, let wait) = error {
        needsAuth = code == 401
        retryAfter = wait
      } else {
        needsAuth = false
        retryAfter = nil
      }
      return .failure(
        .claude,
        source: "error",
        error: ClaudeUsageClient.describe(error),
        needsAuth: needsAuth,
        retryAfterSeconds: retryAfter
      )
    }
  }

  // MARK: - Networking

  private func fetchPayload(token: String) async throws -> [String: Any] {
    var request = URLRequest(url: usageURL)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Glideslope/0.3", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await Self.session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw ClaudeError.fetchFailed(nil, retryAfter: nil)
    }
    guard (200..<300).contains(http.statusCode) else {
      throw ClaudeError.fetchFailed(http.statusCode, retryAfter: ClaudeUsageClient.retryAfter(from: http))
    }
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ClaudeError.malformed
    }
    return json
  }

  // MARK: - Token (read-only)

  private func loadCredential() throws -> ClaudeCredential {
    // 1) Explicit env var (highest precedence). Carries no expiry metadata, so
    //    trust the caller to keep it fresh — this is the `claude setup-token`
    //    long-lived-token path.
    if let envToken = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"]?
      .trimmingCharacters(in: .whitespacesAndNewlines), !envToken.isEmpty {
      return ClaudeCredential(accessToken: envToken, expiresAt: nil)
    }

    // 2) Token file — the reliable channel for a GUI/login-item app, which does
    //    not inherit the shell environment. Default `~/.glideslope/claude-token`,
    //    overridable via GLIDESLOPE_CLAUDE_TOKEN_FILE.
    if let fileToken = tokenFromFile() {
      return ClaudeCredential(accessToken: fileToken, expiresAt: nil)
    }

    #if os(macOS)
    let blob = try securityBlob()
    guard
      let data = blob.data(using: .utf8),
      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let oauth = root["claudeAiOauth"] as? [String: Any],
      let token = (oauth["accessToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !token.isEmpty
    else {
      throw ClaudeError.malformed
    }
    let expiresAt = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
    return ClaudeCredential(accessToken: token, expiresAt: expiresAt)
    #else
    throw ClaudeError.notSignedIn
    #endif
  }

  /// Read a long-lived token from `GLIDESLOPE_CLAUDE_TOKEN_FILE` (or the default
  /// `~/.glideslope/claude-token`). Returns the first non-empty, non-comment
  /// line, trimmed. Nil if the file is absent or empty.
  private func tokenFromFile() -> String? {
    let path: String
    if let override = ProcessInfo.processInfo.environment["GLIDESLOPE_CLAUDE_TOKEN_FILE"], !override.isEmpty {
      path = (override as NSString).expandingTildeInPath
    } else {
      path = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".glideslope/claude-token").path
    }
    guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
      return nil
    }
    for line in contents.split(whereSeparator: \.isNewline) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
        return trimmed
      }
    }
    return nil
  }

  /// Run `security find-generic-password -s "Claude Code-credentials" -w` and
  /// return its stdout (the raw JSON credential blob).
  private func securityBlob() throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = ["find-generic-password", "-s", ClaudeUsageClient.keychainService, "-w"]
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = Pipe()

    do {
      try process.run()
    } catch {
      throw ClaudeError.notSignedIn
    }
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      // Non-zero from `security` almost always means the item is absent
      // (errSecItemNotFound) — i.e. not signed in to Claude Code.
      throw ClaudeError.notSignedIn
    }
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      throw ClaudeError.notSignedIn
    }
    return text
  }

  static func describe(_ error: Error) -> String {
    switch error {
    case ClaudeError.notSignedIn:
      return "not signed in to Claude Code"
    case let ClaudeError.fetchFailed(code?, retryAfter):
      if code == 401 {
        return "token rejected — open Claude Code to refresh"
      }
      if code == 429, let retryAfter {
        return "usage fetch rate-limited; retry after \(ProviderResult.compactDuration(retryAfter))"
      }
      return "usage fetch failed (HTTP \(code))"
    case ClaudeError.fetchFailed(nil, _):
      return "usage fetch failed"
    case ClaudeError.malformed:
      return "unexpected credential/usage format"
    default:
      return String(describing: error)
    }
  }

  private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
    guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
      .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
      return nil
    }
    if let seconds = Double(raw) {
      return max(0, seconds)
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
    guard let date = formatter.date(from: raw) else {
      return nil
    }
    return max(0, date.timeIntervalSinceNow)
  }
}

struct ClaudeCredential: Sendable {
  let accessToken: String
  let expiresAt: Date?
}

enum ClaudeError: Error {
  case notSignedIn
  case fetchFailed(Int?, retryAfter: TimeInterval?)
  case malformed
}

/// Decoder for Anthropic's OAuth usage payload. The broad plan windows live in
/// `five_hour` / `seven_day`; extra model-scoped limits such as Fable live in
/// `limits[]`.
enum ClaudeUsageParser {
  static func windows(from payload: [String: Any], now: Date) -> [UsageWindow] {
    var windows: [UsageWindow] = []
    if let fast = window(.fast, dict: payload["five_hour"], defaultDuration: 5 * 3600, now: now) {
      windows.append(fast)
    }
    if let slow = window(.slow, dict: payload["seven_day"], defaultDuration: 7 * 24 * 3600, now: now) {
      windows.append(slow)
    }
    if let fable = fableWindow(from: payload, now: now) {
      windows.append(fable)
    }
    return windows
  }

  static func hasCompleteBroadWindows(_ windows: [UsageWindow]) -> Bool {
    windows.contains { $0.scope == nil && $0.speed == .fast }
      && windows.contains { $0.scope == nil && $0.speed == .slow }
  }

  private static func window(_ speed: WindowSpeed, dict: Any?, defaultDuration: TimeInterval, now: Date) -> UsageWindow? {
    guard let dict = dict as? [String: Any], let usedPercent = usedPercent(from: dict) else {
      return nil
    }
    let resetAt = resetDate(from: dict) ?? now.addingTimeInterval(defaultDuration)
    return PressureMath.window(
      provider: .claude,
      speed: speed,
      usedPercent: usedPercent,
      resetAt: resetAt,
      limitWindowSeconds: defaultDuration,
      now: now
    )
  }

  private static func fableWindow(from payload: [String: Any], now: Date) -> UsageWindow? {
    guard let limits = payload["limits"] as? [[String: Any]] else {
      return nil
    }

    for limit in limits {
      guard
        string(limit["group"]) == "weekly",
        string(limit["kind"]) == "weekly_scoped",
        bool(limit["is_active"]) == true,
        modelName(from: limit)?.localizedCaseInsensitiveCompare("Fable") == .orderedSame,
        let usedPercent = numeric(limit["percent"])
      else {
        continue
      }

      let resetAt = resetDate(from: limit)
        ?? (payload["seven_day"] as? [String: Any]).flatMap(resetDate(from:))
        ?? now.addingTimeInterval(7 * 24 * 3600)
      return PressureMath.window(
        provider: .claude,
        speed: .slow,
        usedPercent: usedPercent,
        resetAt: resetAt,
        limitWindowSeconds: 7 * 24 * 3600,
        now: now,
        scope: .fable,
        visualStyle: .outerStar
      )
    }

    return nil
  }

  private static func usedPercent(from dict: [String: Any]) -> Double? {
    // `utilization` is already a percent (0–100) in the live payload.
    if let value = numeric(dict["utilization"]) ?? numeric(dict["used_percent"]) ?? numeric(dict["utilization_percent"]) {
      return min(100, max(0, value))
    }
    // Tolerate a fractional `used` field just in case.
    if let fraction = numeric(dict["used"]) ?? numeric(dict["used_fraction"]) {
      return min(100, max(0, fraction * 100))
    }
    return nil
  }

  private static func resetDate(from dict: [String: Any]) -> Date? {
    for key in ["resets_at", "reset_at", "resetsAt"] {
      if let string = dict[key] as? String, let date = parseISO(string) {
        return date
      }
      if let seconds = numeric(dict[key]) {
        return Date(timeIntervalSince1970: seconds > 1_000_000_000_000 ? seconds / 1000 : seconds)
      }
    }
    return nil
  }

  private static func numeric(_ value: Any?) -> Double? {
    if let double = value as? Double { return double }
    if let int = value as? Int { return Double(int) }
    if let string = value as? String { return Double(string) }
    return nil
  }

  private static func string(_ value: Any?) -> String? {
    (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func bool(_ value: Any?) -> Bool? {
    if let bool = value as? Bool { return bool }
    if let int = value as? Int { return int != 0 }
    if let string = value as? String {
      switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
      case "true", "yes", "1": return true
      case "false", "no", "0": return false
      default: return nil
      }
    }
    return nil
  }

  private static func modelName(from dict: [String: Any]) -> String? {
    guard let scope = dict["scope"] as? [String: Any] else {
      return nil
    }
    if let model = scope["model"] as? [String: Any] {
      return string(model["display_name"]) ?? string(model["name"])
    }
    return string(scope["model"])
  }

  private static func parseISO(_ string: String) -> Date? {
    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFractional.date(from: string) { return date }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: string)
  }
}
