import AppKit

enum GaugeIconRenderer {
  static func image(primary: UsageWindow?, weekly: UsageWindow?) -> NSImage {
    let size = NSSize(width: 34, height: 24)
    let image = NSImage(size: size)
    image.lockFocus()

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()

    let center = NSPoint(x: size.width / 2, y: size.height / 2)
    let radius: CGFloat = 10

    drawFace(center: center, radius: radius)

    drawHand(
      center: center,
      length: 12.2,
      width: 2.55,
      pressurePercent: primary?.pressurePercent,
      opacity: 0.94
    )

    drawHand(
      center: center,
      length: 9,
      width: 2.15,
      pressurePercent: weekly?.pressurePercent,
      opacity: 0.82
    )

    NSColor.labelColor.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - 1.65, y: center.y - 1.65, width: 3.3, height: 3.3)).fill()

    image.unlockFocus()
    image.isTemplate = false
    return image
  }

  private static func drawFace(center: NSPoint, radius: CGFloat) {
    let start: CGFloat = 230
    let end: CGFloat = -50
    drawArcStroke(center: center, radius: radius, start: start, end: end, color: NSColor.labelColor.withAlphaComponent(0.82), lineWidth: 4.35)
    drawGradientArc(center: center, radius: radius, start: start, end: end)
  }

  private static func drawGradientArc(center: NSPoint, radius: CGFloat, start: CGFloat, end: CGFloat) {
    let segments = 48

    for index in 0..<segments {
      let startT = CGFloat(index) / CGFloat(segments)
      let endT = CGFloat(index + 1) / CGFloat(segments)
      let segmentStart = start + (end - start) * startT
      let segmentEnd = start + (end - start) * endT

      gradientColor(at: (startT + endT) / 2).setStroke()
      let path = NSBezierPath()
      path.lineWidth = 3.35
      path.lineCapStyle = index == 0 || index == segments - 1 ? .round : .butt
      path.appendArc(withCenter: center, radius: radius, startAngle: segmentStart, endAngle: segmentEnd, clockwise: true)
      path.stroke()
    }
  }

  private static func drawArcStroke(center: NSPoint, radius: CGFloat, start: CGFloat, end: CGFloat, color: NSColor, lineWidth: CGFloat) {
    color.setStroke()
    let path = NSBezierPath()
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    path.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
    path.stroke()
  }

  private static func gradientColor(at position: CGFloat) -> NSColor {
    let clamped = min(1, max(0, position))
    if clamped < 0.5 {
      return mix(.systemBlue, .systemGreen, amount: clamped / 0.5)
    }

    return mix(.systemGreen, .systemRed, amount: (clamped - 0.5) / 0.5)
  }

  private static func mix(_ start: NSColor, _ end: NSColor, amount: CGFloat) -> NSColor {
    let startColor = start.usingColorSpace(.deviceRGB) ?? start
    let endColor = end.usingColorSpace(.deviceRGB) ?? end
    let amount = min(1, max(0, amount))

    return NSColor(
      calibratedRed: startColor.redComponent + (endColor.redComponent - startColor.redComponent) * amount,
      green: startColor.greenComponent + (endColor.greenComponent - startColor.greenComponent) * amount,
      blue: startColor.blueComponent + (endColor.blueComponent - startColor.blueComponent) * amount,
      alpha: 1
    )
  }

  private static func drawHand(center: NSPoint, length: CGFloat, width: CGFloat, pressurePercent: Double?, opacity: CGFloat) {
    NSColor.labelColor.withAlphaComponent(opacity).setFill()
    let angle = angle(for: pressurePercent)
    let radians = angle * .pi / 180
    let direction = CGPoint(x: cos(radians), y: sin(radians))
    let normal = CGPoint(x: -direction.y, y: direction.x)
    let tip = NSPoint(x: center.x + direction.x * length, y: center.y + direction.y * length)
    let base = NSPoint(x: center.x - direction.x * 2.35, y: center.y - direction.y * 2.35)
    let halfWidth = width / 2

    let hand = NSBezierPath()
    hand.move(to: tip)
    hand.line(to: NSPoint(x: center.x + normal.x * halfWidth, y: center.y + normal.y * halfWidth))
    hand.line(to: NSPoint(x: base.x + normal.x * halfWidth * 0.72, y: base.y + normal.y * halfWidth * 0.72))
    hand.line(to: NSPoint(x: base.x - normal.x * halfWidth * 0.72, y: base.y - normal.y * halfWidth * 0.72))
    hand.line(to: NSPoint(x: center.x - normal.x * halfWidth, y: center.y - normal.y * halfWidth))
    hand.close()
    hand.fill()
  }

  private static func angle(for pressurePercent: Double?) -> CGFloat {
    guard let pressurePercent else {
      return 90
    }

    let clamped = min(30, max(-30, pressurePercent))
    let normalized = CGFloat(clamped / 30)
    return 90 + normalized * 130
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
