import AppKit
import SwiftUI

@main
struct GlideslopeApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var controller: StatusItemController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    controller = StatusItemController()
  }
}
