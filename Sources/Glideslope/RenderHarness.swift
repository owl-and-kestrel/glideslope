import AppKit

/// Developer-only preview. Run `Glideslope --render <out.png>` to rasterize the
/// dial against light and dark backgrounds at several usage scenarios, without
/// touching the menu bar or any live credentials.
@MainActor
enum RenderHarness {
  static func run(outputPath: String) {
    let scenarios: [(String, UsageStatus)] = [
      ("typical", sample(codexFast: 28, codexSlow: 55, claudeFast: 74, claudeSlow: 18)),
      ("codex hot", sample(codexFast: 92, codexSlow: 80, claudeFast: 12, claudeSlow: 40)),
      ("claude only", sample(codexFast: nil, codexSlow: nil, claudeFast: 60, claudeSlow: 30))
    ]

    let scale: CGFloat = 12
    let tile = NSSize(width: GaugeIconRenderer.size.width * scale, height: GaugeIconRenderer.size.height * scale)
    let labelStrip: CGFloat = 22
    let padding: CGFloat = 16
    let backgrounds: [(String, NSColor, NSAppearance?)] = [
      ("light", NSColor(white: 0.95, alpha: 1), NSAppearance(named: .aqua)),
      ("dark", NSColor(white: 0.12, alpha: 1), NSAppearance(named: .darkAqua))
    ]

    let cols = scenarios.count
    let rows = backgrounds.count
    let sheet = NSImage(size: NSSize(
      width: padding + CGFloat(cols) * (tile.width + padding),
      height: padding + CGFloat(rows) * (tile.height + labelStrip + padding)
    ))

    sheet.lockFocus()
    // Crisp nearest-neighbor upscale so the preview shows real pixels, not a
    // smeared interpolation of the tiny source image.
    NSGraphicsContext.current?.imageInterpolation = .none
    NSColor(white: 0.3, alpha: 1).setFill()
    NSRect(origin: .zero, size: sheet.size).fill()

    for (rowIndex, background) in backgrounds.enumerated() {
      let appearance = background.2 ?? NSApp.effectiveAppearance
      for (colIndex, scenario) in scenarios.enumerated() {
        let originX = padding + CGFloat(colIndex) * (tile.width + padding)
        let originY = padding + CGFloat(rowIndex) * (tile.height + labelStrip + padding)

        let cell = NSRect(x: originX, y: originY + labelStrip, width: tile.width, height: tile.height)
        background.1.setFill()
        NSBezierPath(roundedRect: cell, xRadius: 10, yRadius: 10).fill()

        var icon = NSImage()
        appearance.performAsCurrentDrawingAppearance {
          icon = GaugeIconRenderer.image(status: scenario.1, scale: scale)
        }
        icon.draw(in: cell, from: .zero, operation: .sourceOver, fraction: 1)

        let label = "\(scenario.0) · \(background.0)"
        let attrs: [NSAttributedString.Key: Any] = [
          .foregroundColor: NSColor.white,
          .font: NSFont.systemFont(ofSize: 12)
        ]
        label.draw(at: NSPoint(x: originX, y: originY), withAttributes: attrs)
      }
    }
    sheet.unlockFocus()

    guard
      let tiff = sheet.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
    else {
      FileHandle.standardError.write(Data("render failed\n".utf8))
      exit(1)
    }
    do {
      try png.write(to: URL(fileURLWithPath: outputPath))
      print("wrote \(outputPath)")
    } catch {
      FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
      exit(1)
    }
  }

  private static func sample(codexFast: Double?, codexSlow: Double?, claudeFast: Double?, claudeSlow: Double?) -> UsageStatus {
    let now = Date()
    func win(_ provider: Provider, _ speed: WindowSpeed, _ used: Double?, _ duration: TimeInterval, _ elapsedFraction: Double) -> UsageWindow? {
      guard let used else { return nil }
      // Place the reset so that `elapsedFraction` of the window has passed.
      let resetAt = now.addingTimeInterval(duration * (1 - elapsedFraction))
      return PressureMath.window(provider: provider, speed: speed, usedPercent: used, resetAt: resetAt, limitWindowSeconds: duration, now: now)
    }
    let codexWindows = [
      win(.codex, .fast, codexFast, 5 * 3600, 0.5),
      win(.codex, .slow, codexSlow, 7 * 24 * 3600, 0.5)
    ].compactMap { $0 }
    let claudeWindows = [
      win(.claude, .fast, claudeFast, 5 * 3600, 0.5),
      win(.claude, .slow, claudeSlow, 7 * 24 * 3600, 0.5)
    ].compactMap { $0 }
    return UsageStatus(generatedAt: now, results: [
      ProviderResult(provider: .codex, ok: !codexWindows.isEmpty, source: "sample", error: codexWindows.isEmpty ? "sample" : nil, windows: codexWindows),
      ProviderResult(provider: .claude, ok: !claudeWindows.isEmpty, source: "sample", error: claudeWindows.isEmpty ? "sample" : nil, windows: claudeWindows)
    ])
  }
}
