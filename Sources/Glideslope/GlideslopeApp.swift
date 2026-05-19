import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private static let sharedDelegate = AppDelegate()
  private var controller: StatusItemController?

  static func main() {
    let app = NSApplication.shared
    app.delegate = sharedDelegate
    app.setActivationPolicy(.accessory)
    app.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    controller = StatusItemController()
  }
}
