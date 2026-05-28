import AppKit

@MainActor
final class StatusItemController {
  private let statusItem = NSStatusBar.system.statusItem(withLength: 24)
  private let store = UsageStore()

  init() {
    if let button = statusItem.button {
      button.bezelStyle = .regularSquare
      button.isBordered = false
      button.imagePosition = .imageOnly
      button.imageScaling = .scaleProportionallyUpOrDown
      button.toolTip = "Glideslope"
    }
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

    for provider in Provider.allCases {
      addProviderSection(provider, to: menu)
    }

    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r"))
    menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

    for item in menu.items {
      item.target = self
    }

    statusItem.menu = menu
  }

  private func addProviderSection(_ provider: Provider, to menu: NSMenu) {
    let result = store.status.result(for: provider)
    let headerTitle = result?.source == "cached" ? "\(provider.displayName) (cached)" : provider.displayName
    let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
    header.image = swatchImage(color: GaugeIconRenderer.providerColor(provider))
    header.isEnabled = false
    menu.addItem(header)
    if let result, result.ok, !result.windows.isEmpty {
      for window in result.windows {
        let item = NSMenuItem(
          title: "    \(window.label): \(window.remainingDisplay) left, \(window.pressureDisplay) \(window.band.label.lowercased())",
          action: nil,
          keyEquivalent: ""
        )
        item.image = dotImage(color: window.band.nsColor)
        item.isEnabled = false
        menu.addItem(item)
      }
    } else {
      let reason = result?.error ?? "usage unavailable"
      let item = NSMenuItem(title: "    \(reason)", action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
    }

    if result?.needsAuth == true {
      let signIn = NSMenuItem(title: "    Sign in to \(provider.displayName)…", action: #selector(signIn(_:)), keyEquivalent: "")
      signIn.representedObject = provider
      menu.addItem(signIn)
    }
  }

  private func updateIcon() {
    statusItem.button?.image = GaugeIconRenderer.image(status: store.status)
    statusItem.button?.toolTip = store.status.summary
  }

  @objc private func signIn(_ sender: NSMenuItem) {
    guard let provider = sender.representedObject as? Provider else { return }
    CLISignIn.launch(provider)
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

  private func swatchImage(color: NSColor) -> NSImage {
    let image = NSImage(size: NSSize(width: 11, height: 11))
    image.lockFocus()
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 9, height: 9), xRadius: 2.5, yRadius: 2.5).fill()
    image.unlockFocus()
    image.isTemplate = false
    return image
  }
}
