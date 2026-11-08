import AppKit
import SwiftUI

/// An earbuds glyph inside a ring that fills with the earbuds' battery level.
struct BatteryRing: View {
    let level: Int?
    var charging = false
    var size: CGFloat = 32
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(level ?? 0) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "airpodspro")
                .font(.system(size: size * 0.42, weight: .medium))
        }
        .frame(width: size, height: size)
        .animation(.snappy, value: level)
        .accessibilityElement()
        .accessibilityLabel(level.map { "Earbuds battery \($0) percent" } ?? "Earbuds battery unavailable")
    }

    private var color: Color {
        guard let level else { return .clear }
        if charging { return .green }
        return level <= 20 ? .red : .accentColor
    }
}

/// Menu bar version: a template image so it follows the menu bar's light/dark appearance.
enum MenuBarIcon {
    static func image(level: Int?, connected: Bool) -> NSImage {
        let size = NSSize(width: 20, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let diameter: CGFloat = 16.5
            let ringRect = NSRect(x: (rect.width - diameter) / 2, y: (rect.height - diameter) / 2,
                                  width: diameter, height: diameter).insetBy(dx: 0.9, dy: 0.9)
            let center = NSPoint(x: ringRect.midX, y: ringRect.midY)
            let radius = ringRect.width / 2

            // Track
            NSColor.black.withAlphaComponent(connected ? 0.28 : 0.2).setStroke()
            let track = NSBezierPath(ovalIn: ringRect)
            track.lineWidth = 1.8
            track.stroke()

            // Battery arc, clockwise from 12 o'clock.
            if connected, let level, level > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                              endAngle: 90 - 360 * CGFloat(min(level, 100)) / 100, clockwise: true)
                arc.lineWidth = 1.8
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }

            // Glyph
            let config = NSImage.SymbolConfiguration(pointSize: 7.5, weight: .semibold)
            if let glyph = NSImage(systemSymbolName: "airpodspro", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let g = glyph.size
                glyph.draw(in: NSRect(x: center.x - g.width / 2, y: center.y - g.height / 2, width: g.width, height: g.height),
                           from: .zero, operation: .sourceOver, fraction: connected ? 1 : 0.45)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = level.map { "Buds Control, battery \($0)%" } ?? "Buds Control"
        return image
    }
}
