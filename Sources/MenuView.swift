import SwiftUI

struct MenuView: View {
    @ObservedObject var buds: BudsController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Spacing 0: glass shapes only blend when they touch, so nothing nearby picks up the lens.
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: 10) {
                header
                if buds.link == .connected {
                    modes
                    if buds.mode == .anc, !buds.availableLevels.isEmpty {
                        levels.transition(.blurReplace)
                    }
                    batteries
                } else {
                    disconnected
                }
            }
        }
        .padding(12)
        .frame(width: 256)
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: buds.mode)
        .animation(.snappy(duration: 0.22), value: buds.link)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            BatteryRing(level: buds.link == .connected ? buds.budsBattery : nil,
                        charging: buds.left?.charging == true || buds.right?.charging == true,
                        size: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text(buds.deviceName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
            Menu {
                Button("Settings…") { openSettings() }.keyboardShortcut(",")
                Button("Reconnect") { buds.reconnect() }
                Divider()
                Button("Quit Buds Control") { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
        }
    }

    private var subtitle: String {
        switch buds.link {
        case .connected:
            if let level = buds.budsBattery { return "\(level)% · \(buds.mode?.title ?? "Connected")" }
            return buds.mode?.title ?? "Connected"
        case .connecting: return "Connecting…"
        case .searching: return "Not connected"
        }
    }

    // MARK: Modes and levels — lens-style segmented controls (see LiquidSegmented)

    private var modes: some View {
        LiquidSegmented(items: [NoiseMode.off, .transparency, .anc], selection: buds.mode,
                        onSelect: { buds.setMode($0) }) { mode, selected in
            HStack(spacing: 5) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .symbolEffect(.bounce, value: selected)
                if selected {
                    Text(mode.shortTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .help(mode.title)
            .accessibilityLabel(mode.title)
        } widthFor: { _, selected in selected ? nil : 40 }
    }

    private var levels: some View {
        LiquidSegmented(items: buds.availableLevels, selection: buds.level, height: 22,
                        onSelect: { buds.setMode(.anc, level: $0) }) { level, selected in
            Text(level.title)
                .font(.caption2.weight(selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .lineLimit(1)
        }
    }

    // MARK: Battery — one compact line

    private var batteries: some View {
        HStack(spacing: 0) {
            BatteryLabel(symbol: "airpod.left", battery: buds.left)
            Spacer(minLength: 0)
            BatteryLabel(symbol: "airpod.right", battery: buds.right)
            Spacer(minLength: 0)
            BatteryLabel(symbol: "airpods.chargingcase", battery: buds.caseBattery)
        }
        .padding(.horizontal, 6)
    }

    // MARK: Disconnected

    private var disconnected: some View {
        HStack(spacing: 8) {
            if buds.link == .connecting { ProgressView().controlSize(.small) }
            Text(buds.link == .connecting ? "Connecting…" : "Buds not connected to this Mac")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if buds.link != .connecting {
                Button("Retry") { buds.reconnect() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate()
    }
}

private struct BatteryLabel: View {
    let symbol: String
    let battery: BudsController.Battery?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(.secondary)
            if battery?.charging == true {
                Image(systemName: "bolt.fill").font(.system(size: 8)).foregroundStyle(.green)
            }
            Text(battery.map { "\($0.level)%" } ?? "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(battery.map { $0.level <= 20 && !$0.charging } == true ? .red : .primary)
        }
    }
}
