import Foundation
import Testing
@testable import Glideslope

@Suite("Claude usage parser")
struct ClaudeUsageParserTests {
  @Test("partial broad-window responses are not authoritative")
  func partialBroadWindowResponseIsIncomplete() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let payload: [String: Any] = [
      "five_hour": [
        "utilization": 25,
        "resets_at": "2027-01-15T09:00:00Z"
      ],
      "limits": [[
        "group": "weekly",
        "kind": "weekly_scoped",
        "is_active": true,
        "percent": 60,
        "scope": ["model": ["display_name": "Fable"]],
        "resets_at": "2027-01-20T09:00:00Z"
      ]]
    ]

    let windows = ClaudeUsageParser.windows(from: payload, now: now)

    #expect(windows.map(\.label).contains("Fable"))
    #expect(!ClaudeUsageParser.hasCompleteBroadWindows(windows))
  }

  @Test("both broad windows form a complete authoritative response")
  func completeBroadWindowResponseIsAuthoritative() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let payload: [String: Any] = [
      "five_hour": [
        "utilization": 25,
        "resets_at": "2027-01-15T09:00:00Z"
      ],
      "seven_day": [
        "utilization": 40,
        "resets_at": "2027-01-20T09:00:00Z"
      ]
    ]

    let windows = ClaudeUsageParser.windows(from: payload, now: now)

    #expect(ClaudeUsageParser.hasCompleteBroadWindows(windows))
    #expect(windows.map(\.speed) == [.fast, .slow])
  }
}
