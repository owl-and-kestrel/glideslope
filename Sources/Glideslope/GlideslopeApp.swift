import SwiftUI

@main
struct GlideslopeApp: App {
  @State private var store = UsageStore()

  var body: some Scene {
    MenuBarExtra {
      GlideslopeMenu(store: store)
        .task {
          await store.runRefreshLoop()
        }
    } label: {
      GlideslopeIcon(
        primary: store.status.window(id: "primary_window")?.band ?? .unknown,
        weekly: store.status.window(id: "secondary_window")?.band ?? .unknown
      )
      .frame(width: 22, height: 16)
      .help(store.status.summary)
    }
    .menuBarExtraStyle(.menu)
  }
}
