import AppKit

enum GaugeIconRenderer {
  static func image(primary: UsageWindow?, weekly: UsageWindow?) -> NSImage {
    let size = NSSize(width: 24, height: 18)
    let center = NSPoint(x: size.width / 2, y: size.height / 2)
    let radius: CGFloat = 7.6
    let image = NSImage(size: size)

    image.lockFocus()
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()

    drawDial(center: center, radius: radius)
    drawHand(center: center, length: 9.25, width: 2, pressurePercent: primary?.pressurePercent, alpha: 0.94)
    drawHand(center: center, length: 6.75, width: 1.7, pressurePercent: weekly?.pressurePercent, alpha: 0.82)

    NSColor.labelColor.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - 1.32, y: center.y - 1.32, width: 2.64, height: 2.64)).fill()

    image.unlockFocus()
    image.isTemplate = false
    return image
  }

  private static func drawDial(center: NSPoint, radius: CGFloat) {
    let start: CGFloat = 230
    let sweep: CGFloat = -280

    strokeArc(center: center, radius: radius, start: start, end: start + sweep, color: NSColor.labelColor.withAlphaComponent(0.82), width: 3.2, rounded: true)

    let colors = [
      NSColor(calibratedRed: 0.02, green: 0.48, blue: 0.95, alpha: 1),
      NSColor(calibratedRed: 0.07, green: 0.57, blue: 0.78, alpha: 1),
      NSColor(calibratedRed: 0.13, green: 0.65, blue: 0.55, alpha: 1),
      NSColor(calibratedRed: 0.21, green: 0.72, blue: 0.30, alpha: 1),
      NSColor(calibratedRed: 0.54, green: 0.62, blue: 0.25, alpha: 1),
      NSColor(calibratedRed: 0.78, green: 0.45, blue: 0.22, alpha: 1),
      NSColor(calibratedRed: 1.00, green: 0.23, blue: 0.19, alpha: 1)
    ]

    let segmentSweep = sweep / CGFloat(colors.count)
    for index in colors.indices {
      let segmentStart = start + CGFloat(index) * segmentSweep
      let segmentEnd = segmentStart + segmentSweep
      strokeArc(center: center, radius: radius, start: segmentStart, end: segmentEnd, color: colors[index], width: 2.45, rounded: index == colors.startIndex || index == colors.index(before: colors.endIndex))
    }
  }

  private static func strokeArc(center: NSPoint, radius: CGFloat, start: CGFloat, end: CGFloat, color: NSColor, width: CGFloat, rounded: Bool) {
    color.setStroke()
    let path = NSBezierPath()
    path.lineWidth = width
    path.lineCapStyle = rounded ? .round : .butt
    path.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
    path.stroke()
  }

  private static func drawHand(center: NSPoint, length: CGFloat, width: CGFloat, pressurePercent: Double?, alpha: CGFloat) {
    let radians = angle(for: pressurePercent) * .pi / 180
    let dx = cos(radians)
    let dy = sin(radians)
    let nx = -dy
    let ny = dx
    let halfWidth = width / 2
    let tail: CGFloat = 2.05
    let tailWidth = halfWidth * 0.72

    let tip = NSPoint(x: center.x + dx * length, y: center.y + dy * length)
    let shoulderLeft = NSPoint(x: center.x + nx * halfWidth, y: center.y + ny * halfWidth)
    let shoulderRight = NSPoint(x: center.x - nx * halfWidth, y: center.y - ny * halfWidth)
    let tailCenter = NSPoint(x: center.x - dx * tail, y: center.y - dy * tail)
    let tailLeft = NSPoint(x: tailCenter.x + nx * tailWidth, y: tailCenter.y + ny * tailWidth)
    let tailRight = NSPoint(x: tailCenter.x - nx * tailWidth, y: tailCenter.y - ny * tailWidth)

    NSColor.labelColor.withAlphaComponent(alpha).setFill()
    let hand = NSBezierPath()
    hand.move(to: tip)
    hand.line(to: shoulderLeft)
    hand.line(to: tailLeft)
    hand.line(to: tailRight)
    hand.line(to: shoulderRight)
    hand.close()
    hand.fill()
  }

  private static func angle(for pressurePercent: Double?) -> CGFloat {
    guard let pressurePercent else {
      return 90
    }

    let bounded = min(30, max(-30, pressurePercent))
    return 90 + CGFloat(bounded / 30) * 130
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
