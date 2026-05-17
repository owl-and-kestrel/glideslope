import AppKit

@MainActor
final class StatusItemController {
  private let statusItem = NSStatusBar.system.statusItem(withLength: 38)
  private let store = UsageStore()

  init() {
    statusItem.button?.imagePosition = .imageOnly
    statusItem.button?.imageScaling = .scaleProportionallyUpOrDown
    statusItem.button?.toolTip = "Glideslope"
    statusItem.menu = makeMenu()

    updateIcon()

    Task {
      await store.refresh()
      updateMenu()
      updateIcon()
      startRefreshLoop()
    }
  }

  private func startRefreshLoop() {
    Task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(60))
        await store.refresh()
        updateMenu()
        updateIcon()
      }
    }
  }

  private func makeMenu() -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    return menu
  }

  private func updateMenu() {
    let menu = statusItem.menu ?? makeMenu()
    menu.removeAllItems()

    if store.status.ok {
      for window in store.status.windows {
        let item = NSMenuItem(title: "\(window.label): \(window.remainingDisplay) left, \(window.pressureDisplay)", action: nil, keyEquivalent: "")
        item.image = dotImage(color: window.band.nsColor)
        menu.addItem(item)
      }
    } else {
      menu.addItem(NSMenuItem(title: "Usage unavailable", action: nil, keyEquivalent: ""))
      if let error = store.status.error {
        menu.addItem(NSMenuItem(title: error, action: nil, keyEquivalent: ""))
      }
    }

    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r"))
    menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

    for item in menu.items {
      item.target = self
    }

    statusItem.menu = menu
  }

  private func updateIcon() {
    let primary = store.status.window(id: "primary_window")
    let weekly = store.status.window(id: "secondary_window")
    statusItem.button?.image = GaugeIconRenderer.image(primary: primary, weekly: weekly)
    statusItem.button?.toolTip = store.status.summary
  }

  @objc private func refresh() {
    Task {
      await store.refresh()
      updateMenu()
      updateIcon()
    }
  }

  @objc private func quit() {
    NSApplication.shared.terminate(nil)
  }

  private func dotImage(color: NSColor) -> NSImage {
    let image = NSImage(size: NSSize(width: 10, height: 10))
    image.lockFocus()
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 8, height: 8)).fill()
    image.unlockFocus()
    image.isTemplate = false
    return image
  }
}
