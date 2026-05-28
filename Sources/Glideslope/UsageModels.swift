import Foundation

/// A usage backend Glideslope tracks. Each provider contributes a fast and a
/// slow window, and is distinguished on the dial by hand color.
enum Provider: String, Codable, CaseIterable, Sendable {
  case codex
  case claude

  var displayName: String {
    switch self {
    case .codex: "Codex"
    case .claude: "Claude"
    }
  }
}

/// The two cadences every provider exposes. `fast` is the short rolling window
/// (~5h); `slow` is the long window (weekly). The gauge draws `fast` on the
/// outer ring (background) and `slow` on the inner ring (foreground).
enum WindowSpeed: String, Codable, Sendable {
  case fast
  case slow

  var displayName: String {
    switch self {
    case .fast: "5h"
    case .slow: "Weekly"
    }
  }
}

enum PressureBand: String, Codable, Sendable {
  case high
  case good
  case low
  case unknown

  init(pressurePercent: Double) {
    if pressurePercent > 5 {
      self = .high
    } else if pressurePercent < -5 {
      self = .low
    } else {
      self = .good
    }
  }

  var label: String {
    switch self {
    case .high:
      "High"
    case .good:
      "Good"
    case .low:
      "Low"
    case .unknown:
      "Unknown"
    }
  }
}

struct UsageWindow: Codable, Identifiable, Sendable {
  let provider: Provider
  let speed: WindowSpeed
  let usedPercent: Double
  let remainingPercent: Double
  let expectedRemainingPercent: Double
  let pressurePercent: Double
  let resetAt: Date
  let limitWindowSeconds: TimeInterval

  var id: String { "\(provider.rawValue)_\(speed.rawValue)" }

  /// Short label for the dropdown ("5h", "Weekly").
  var label: String { speed.displayName }

  /// Provider-qualified label for the menu-bar summary ("Codex 5h").
  var qualifiedLabel: String { "\(provider.displayName) \(speed.displayName)" }

  var band: PressureBand {
    PressureBand(pressurePercent: pressurePercent)
  }

  var remainingDisplay: String {
    "\(Int(remainingPercent.rounded()))%"
  }

  var pressureDisplay: String {
    let rounded = Int(pressurePercent.rounded())
    return rounded > 0 ? "+\(rounded)%" : "\(rounded)%"
  }
}

/// The outcome of polling a single provider. Kept even when empty so the menu
/// can explain *why* a provider has no hands (expired token, fetch error).
struct ProviderResult: Sendable {
  let provider: Provider
  let ok: Bool
  let source: String
  let error: String?
  let windows: [UsageWindow]
  /// True when the failure is a credential problem the user can fix by signing
  /// in (vs. a transient network/rate-limit error).
  var needsAuth: Bool = false

  static func failure(_ provider: Provider, source: String, error: String, needsAuth: Bool = false) -> ProviderResult {
    ProviderResult(provider: provider, ok: false, source: source, error: error, windows: [], needsAuth: needsAuth)
  }
}

struct UsageStatus: Sendable {
  var generatedAt: Date = .now
  var results: [ProviderResult] = []

  var windows: [UsageWindow] {
    results.flatMap(\.windows)
  }

  var ok: Bool { !windows.isEmpty }

  func result(for provider: Provider) -> ProviderResult? {
    results.first { $0.provider == provider }
  }

  func window(provider: Provider, speed: WindowSpeed) -> UsageWindow? {
    windows.first { $0.provider == provider && $0.speed == speed }
  }

  /// The most constrained window across every provider — the one with the
  /// lowest pace pressure.
  var worst: UsageWindow? {
    windows.min { $0.pressurePercent < $1.pressurePercent }
  }

  var summary: String {
    guard let worst else {
      return "Glideslope: usage unavailable"
    }
    return "\(worst.qualifiedLabel) \(worst.pressureDisplay) \(worst.band.label.lowercased())"
  }
}

/// Shared normalization so both provider clients derive pace pressure the same
/// way. `usedPercent` is 0–100; the caller is responsible for unit conversion.
enum PressureMath {
  static func window(
    provider: Provider,
    speed: WindowSpeed,
    usedPercent: Double,
    resetAt: Date,
    limitWindowSeconds: TimeInterval,
    now: Date
  ) -> UsageWindow {
    let used = min(100, max(0, usedPercent))
    let secondsRemaining = max(0, resetAt.timeIntervalSince(now))
    let duration = max(60, limitWindowSeconds)
    let expectedRemaining = min(1, max(0, secondsRemaining / duration))
    let actualRemaining = min(1, max(0, 1 - used / 100))
    let pressure = actualRemaining - expectedRemaining

    return UsageWindow(
      provider: provider,
      speed: speed,
      usedPercent: used,
      remainingPercent: actualRemaining * 100,
      expectedRemainingPercent: expectedRemaining * 100,
      pressurePercent: pressure * 100,
      resetAt: resetAt,
      limitWindowSeconds: duration
    )
  }
}
