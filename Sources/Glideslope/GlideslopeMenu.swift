import AppKit
import SwiftUI

struct GlideslopeMenu: View {
  let store: UsageStore

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if store.status.ok {
        ForEach(store.status.windows) { window in
          WindowRow(window: window)
        }
      } else {
        Text("Usage unavailable")
        if let error = store.status.error {
          Text(error)
            .foregroundStyle(.secondary)
        }
      }

      Divider()

      Button("Refresh") {
        Task {
          await store.refresh()
        }
      }

      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
    }
  }
}

private struct WindowRow: View {
  let window: UsageWindow

  var body: some View {
    HStack {
      Circle()
        .fill(window.band.color)
        .frame(width: 8, height: 8)

      Text(window.label)
      Spacer()
      Text("\(window.remainingDisplay) left")
        .foregroundStyle(.secondary)
      Text(window.pressureDisplay)
        .foregroundStyle(.secondary)
    }
  }
}
