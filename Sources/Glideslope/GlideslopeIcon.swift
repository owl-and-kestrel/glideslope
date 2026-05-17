import SwiftUI

struct GlideslopeIcon: View {
  let primary: PressureBand
  let weekly: PressureBand

  var body: some View {
    HStack(spacing: 2) {
      Capsule()
        .fill(primary.color)
        .overlay(Capsule().stroke(.primary.opacity(0.18), lineWidth: 0.5))
      Capsule()
        .fill(weekly.color)
        .overlay(Capsule().stroke(.primary.opacity(0.18), lineWidth: 0.5))
    }
    .padding(.vertical, 2)
    .accessibilityLabel("Glideslope")
  }
}

enum PressureBand: String, Codable {
  case high
  case good
  case low
  case unknown

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

  var color: Color {
    switch self {
    case .high:
      Color(red: 0.16, green: 0.43, blue: 0.92)
    case .good:
      Color(red: 0.15, green: 0.67, blue: 0.36)
    case .low:
      Color(red: 0.89, green: 0.12, blue: 0.18)
    case .unknown:
      Color.secondary.opacity(0.5)
    }
  }

  init(pressurePercent: Double) {
    if pressurePercent > 5 {
      self = .high
    } else if pressurePercent < -5 {
      self = .low
    } else {
      self = .good
    }
  }
}
