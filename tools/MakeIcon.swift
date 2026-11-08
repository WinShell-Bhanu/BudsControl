// Renders the app icon (two earbuds inside a battery ring on a glassy blue squircle) into an
// .iconset folder. Drawn from scratch with Core Graphics; no SF Symbols, which Apple's license
// doesn't allow in app icons.
// Usage: swift tools/MakeIcon.swift <output.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

/// One earbud, drawn for the left ear; `mirror` flips it for the right.
func earbud(center: NSPoint, size s: CGFloat, mirror: Bool) {
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform()
    t.translateX(by: center.x, yBy: center.y)
    if mirror { t.scaleX(by: -1, yBy: 1) }
    t.rotate(byDegrees: 14)
    t.concat()

    let headR = s * 0.25
    let stemW = s * 0.15
    let stemH = s * 0.62

    // Stem
    let stem = NSBezierPath(roundedRect: NSRect(x: headR * 0.25 - stemW / 2, y: -stemH, width: stemW, height: stemH),
                            xRadius: stemW / 2, yRadius: stemW / 2)
    // Head
    let head = NSBezierPath(ovalIn: NSRect(x: -headR, y: -headR * 0.9, width: headR * 2, height: headR * 1.9))
    let body = NSBezierPath()
    body.append(stem)
    body.append(head)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = s * 0.06
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.025)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.white.setFill()
    stem.fill()
    head.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Soft shading for a bit of volume.
    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    NSGradient(colors: [NSColor(white: 1, alpha: 0), NSColor(srgbRed: 0.75, green: 0.8, blue: 0.92, alpha: 0.55)])!
        .draw(in: NSRect(x: -headR, y: -stemH, width: headR * 2, height: stemH + headR), angle: 0)
    NSGraphicsContext.restoreGraphicsState()

    // Silicone ear tip, peeking out on the inner side.
    NSColor(srgbRed: 0.80, green: 0.84, blue: 0.93, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: headR * 0.55, y: -headR * 0.25, width: headR * 0.6, height: headR * 0.75)).fill()

    NSGraphicsContext.restoreGraphicsState()
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    // macOS icon grid: 824/1024 body with a soft drop shadow.
    let body = NSRect(x: s * 0.098, y: s * 0.098, width: s * 0.804, height: s * 0.804)
    let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(srgbRed: 0.40, green: 0.70, blue: 1.00, alpha: 1),
                        NSColor(srgbRed: 0.16, green: 0.36, blue: 0.95, alpha: 1),
                        NSColor(srgbRed: 0.33, green: 0.18, blue: 0.80, alpha: 1)])!
        .draw(in: shape, angle: -70)

    // Glass sheen on the upper half and a thin bright rim.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.35), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.45).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: s * 0.004, dy: s * 0.004),
                           xRadius: body.width * 0.222, yRadius: body.width * 0.222)
    rim.lineWidth = max(1, s * 0.006)
    rim.stroke()

    // Battery ring, echoing the menu bar icon: faint track plus a three-quarter arc.
    let center = NSPoint(x: s / 2, y: s / 2)
    let radius = s * 0.285
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = s * 0.035
    NSColor.white.withAlphaComponent(0.22).setStroke()
    track.stroke()
    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 270, clockwise: true)
    arc.lineWidth = s * 0.035
    arc.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.95).setStroke()
    arc.stroke()

    earbud(center: NSPoint(x: s * 0.385, y: s * 0.585), size: s * 0.3, mirror: false)
    earbud(center: NSPoint(x: s * 0.615, y: s * 0.585), size: s * 0.3, mirror: true)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try! render(size * scale).write(to: out.appendingPathComponent(name))
    }
}
