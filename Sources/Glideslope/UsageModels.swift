import Foundation

enum PressureBand: String, Codable {
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

struct UsageStatus: Codable {
  var ok: Bool = false
  var source: String = "empty"
  var error: String?
  var generatedAt: Date = .now
  var windows: [UsageWindow] = []

  var summary: String {
    guard let worst = windows.sorted(by: { $0.pressurePercent < $1.pressurePercent }).first else {
      return "Glideslope: usage unavailable"
    }
    return "\(worst.label) \(worst.pressureDisplay) \(worst.band.label.lowercased())"
  }

  func window(id: String) -> UsageWindow? {
    windows.first { $0.id == id }
  }
}

struct UsageWindow: Codable, Identifiable {
  let id: String
  let label: String
  let usedPercent: Double
  let remainingPercent: Double
  let expectedRemainingPercent: Double
  let pressurePercent: Double
  let resetAt: Date
  let limitWindowSeconds: TimeInterval

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

struct UsagePayload: Decodable {
  let rateLimit: RateLimit

  enum CodingKeys: String, CodingKey {
    case rateLimit = "rate_limit"
  }
}

struct RateLimit: Decodable {
  let primaryWindow: RateLimitWindow?
  let secondaryWindow: RateLimitWindow?

  enum CodingKeys: String, CodingKey {
    case primaryWindow = "primary_window"
    case secondaryWindow = "secondary_window"
  }
}

struct RateLimitWindow: Decodable {
  let usedPercent: Double
  let resetAt: TimeInterval
  let limitWindowSeconds: TimeInterval

  enum CodingKeys: String, CodingKey {
    case usedPercent = "used_percent"
    case resetAt = "reset_at"
    case limitWindowSeconds = "limit_window_seconds"
  }
}

struct AuthFile: Decodable {
  let tokens: AuthTokens?
}

struct AuthTokens: Decodable {
  let accessToken: String?
  let accountId: String?

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case accountId = "account_id"
  }
}
