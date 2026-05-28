import AppKit

/// Renders the menu-bar dial as a dark circle with a dotted gauge scale and two
/// (or four) bold hands. The hands are the point of the program, so they are
/// large and vivid; the scale recedes to white dots, and the only colored part
/// of the scale is a bright-red redline cluster on the hot end.
///
/// The canvas is square so the dial never crops against the menu bar.
///
/// Deconfliction:
///   • provider  -> hand color (Codex teal, Claude coral)
///   • window    -> radius + depth: the fast (~5h) window is a long hand drawn
///                  first (background); the slow (weekly) window is a shorter
///                  hand drawn last (foreground).
enum GaugeIconRenderer {
  static let size = NSSize(width: 22, height: 22)
  private static let circleRadius: CGFloat = 10.5
  private static let dotRadius: CGFloat = 8.6
  private static let dotCount = 16
  private static let dialStart: CGFloat = 230
  private static let dialSweep: CGFloat = -280
  /// Consumption fraction beyond which the scale dots turn red.
  private static let redlineFraction: CGFloat = 0.78

  @MainActor
  static func image(status: UsageStatus, scale: CGFloat = 1) -> NSImage {
    let center = NSPoint(x: size.width / 2, y: size.height / 2)
    let image = NSImage(size: NSSize(width: size.width * scale, height: size.height * scale))

    image.lockFocus()
    if scale != 1 {
      let transform = NSAffineTransform()
      transform.scale(by: scale)
      transform.concat()
    }
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()

    drawFace(center: center)
    drawScale(center: center)

    // Draw long (slow) lines first, then short (fast) lines on top, so a short
    // outer line is never hidden under a long line when their angles align.
    // Within each band, the most-constrained (lowest pressure) draws last.
    let ordered = status.windows.sorted { a, b in
      if a.speed != b.speed { return a.speed == .slow }
      return a.pressurePercent > b.pressurePercent
    }
    for window in ordered {
      drawHand(center: center, window: window)
    }

    drawHub(center: center)

    image.unlockFocus()
    image.isTemplate = false
    return image
  }

  // MARK: - Face & scale

  private static func drawFace(center: NSPoint) {
    let rect = NSRect(x: center.x - circleRadius, y: center.y - circleRadius, width: circleRadius * 2, height: circleRadius * 2)
    NSColor(calibratedWhite: 0.09, alpha: 0.96).setFill()
    NSBezierPath(ovalIn: rect).fill()
  }

  private static func drawScale(center: NSPoint) {
    // Small white dots form the scale up to the redline — kept subtle so the
    // hands dominate.
    let dotR: CGFloat = 0.62
    NSColor(calibratedWhite: 0.90, alpha: 0.8).setFill()
    for index in 0..<dotCount {
      let fraction = CGFloat(index) / CGFloat(dotCount - 1)
      if fraction >= redlineFraction { continue }
      let angle = (dialStart + dialSweep * fraction) * .pi / 180
      let point = NSPoint(x: center.x + cos(angle) * dotRadius, y: center.y + sin(angle) * dotRadius)
      NSBezierPath(ovalIn: NSRect(x: point.x - dotR, y: point.y - dotR, width: dotR * 2, height: dotR * 2)).fill()
    }

    // The redline is a solid bright-red arc over the hot end, not dots.
    let redStart = dialStart + dialSweep * redlineFraction
    let redEnd = dialStart + dialSweep
    let red = NSColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
    red.setStroke()
    let arc = NSBezierPath()
    arc.lineWidth = 2.3
    arc.lineCapStyle = .round
    arc.appendArc(withCenter: center, radius: dotRadius, startAngle: redStart, endAngle: redEnd, clockwise: true)
    arc.stroke()
  }

  // MARK: - Hands

  // Dots sit at `dotRadius` = 8.6; the circle face ends at `circleRadius` = 10.5.
  // The two window kinds occupy different radial bands so they never swallow
  // each other when their angles align.
  private static func drawHand(center: NSPoint, window: UsageWindow) {
    let radians = angle(for: window) * .pi / 180
    let dx = cos(radians)
    let dy = sin(radians)
    let nx = -dy
    let ny = dx

    // (r) = distance along the hand's angle, (t) = tangential offset.
    func point(_ r: CGFloat, _ t: CGFloat = 0) -> NSPoint {
      NSPoint(x: center.x + dx * r + nx * t, y: center.y + dy * r + ny * t)
    }

    let line = NSBezierPath()
    let colorWidth: CGFloat
    switch window.speed {
    case .slow:
      // Long window (weekly): a long line from a short tail through the hub out
      // past the tick marks.
      line.move(to: point(-1.2))
      line.line(to: point(9.4))
      colorWidth = 1.9
    case .fast:
      // Short window (5h): a short bold line in the outer band, from the edge
      // inward past the tick marks — an emphasized tick.
      line.move(to: point(10.3))
      line.line(to: point(7.5))
      colorWidth = 2.1
    }
    line.lineCapStyle = .round

    // Thin dark edge under the bright color line for separation on overlaps.
    NSColor.black.setStroke()
    line.lineWidth = colorWidth + 0.8
    line.stroke()
    providerColor(window.provider).setStroke()
    line.lineWidth = colorWidth
    line.stroke()
  }

  private static func drawHub(center: NSPoint) {
    let r: CGFloat = 0.9
    let cap = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    cap.fill()
  }

  // MARK: - Colors

  /// Provider accent for the hands and the dropdown swatch. Tuned to read as
  /// vivid teal / coral on the dark face, and distinct from each other.
  static func providerColor(_ provider: Provider) -> NSColor {
    switch provider {
    case .codex:
      NSColor(calibratedRed: 0.16, green: 0.82, blue: 0.84, alpha: 1)
    case .claude:
      NSColor(calibratedRed: 1.00, green: 0.55, blue: 0.34, alpha: 1)
    }
  }

  // MARK: - Pace-relative angle

  static func angle(for window: UsageWindow?) -> CGFloat {
    guard let window else {
      return 90
    }
    return angle(
      usedPercent: window.usedPercent,
      expectedRemainingPercent: window.expectedRemainingPercent
    )
  }

  static func angle(usedPercent: Double, expectedRemainingPercent: Double) -> CGFloat {
    let position = dialPosition(
      usedPercent: usedPercent,
      expectedRemainingPercent: expectedRemainingPercent
    )
    return dialStart + CGFloat(position / 100) * dialSweep
  }

  static func dialPosition(usedPercent: Double, expectedRemainingPercent: Double) -> Double {
    let used = min(100, max(0, usedPercent))
    let expectedUsed = min(100, max(0, 100 - expectedRemainingPercent))

    // The dial is pace-relative: 0% consumed is the left endpoint, exactly
    // on-track is the center, and fully consumed is the right endpoint.
    if used <= 0 {
      return 0
    }
    if used >= 100 {
      return 100
    }
    if expectedUsed <= 0 {
      return 50 + used / 100 * 50
    }
    if expectedUsed >= 100 {
      return used / 100 * 50
    }
    if used <= expectedUsed {
      return used / expectedUsed * 50
    }
    return 50 + (used - expectedUsed) / (100 - expectedUsed) * 50
  }
}

extension PressureBand {
  var nsColor: NSColor {
    switch self {
    case .high:
      NSColor.systemBlue
    case .good:
      NSColor.systemGreen
    case .low:
      NSColor.systemRed
    case .unknown:
      NSColor.systemGray
    }
  }
}
