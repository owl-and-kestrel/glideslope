import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private static let sharedDelegate = AppDelegate()
  private var controller: StatusItemController?

  static func main() {
    let arguments = CommandLine.arguments
    if let renderIndex = arguments.firstIndex(of: "--render") {
      let output = renderIndex + 1 < arguments.count ? arguments[renderIndex + 1] : "glideslope-preview.png"
      RenderHarness.run(outputPath: output)
      return
    }

    let app = NSApplication.shared
    app.delegate = sharedDelegate
    app.setActivationPolicy(.accessory)
    app.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    controller = StatusItemController()
  }
}
