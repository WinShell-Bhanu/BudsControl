import SwiftUI
import IOBluetooth

struct BudsControlApp: App {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var buds = AppModel.shared.buds

    init() {
        AppModel.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(buds: buds)
        } label: {
            // Earbuds glyph inside a ring showing the earbuds' battery; dimmed while disconnected.
            Image(nsImage: MenuBarIcon.image(level: buds.budsBattery, connected: buds.link == .connected))
        }
        .menuBarExtraStyle(.window)

        Window("Buds Control Settings", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
    }
}

let args = CommandLine.arguments
if args.contains("--sdp") {
    // Lists the RFCOMM services the buds advertise, to debug channel selection.
    let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
    guard let d = paired.first(where: { $0.isConnected() && ($0.name ?? "").lowercased().contains("buds") }) else {
        print("no connected buds"); exit(1)
    }
    print("performSDPQuery:", d.performSDPQuery(nil))
    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
        for case let r as IOBluetoothSDPServiceRecord in d.services ?? [] {
            var ch: BluetoothRFCOMMChannelID = 0
            let hasRFCOMM = r.getRFCOMMChannelID(&ch) == kIOReturnSuccess
            print("\(r.getServiceName() ?? "?")  rfcomm=\(hasRFCOMM ? String(ch) : "-")")
        }
        exit(0)
    }
    RunLoop.main.run()
} else if let i = args.firstIndex(of: "--watch") {
    // Logs everything the buds send, for N seconds.
    let seconds = Double(args.count > i + 1 ? args[i + 1] : "60") ?? 60
    let started = Date()
    func stamp() -> String { String(format: "[%6.2fs] ", Date().timeIntervalSince(started)) }
    let buds = BudsController()
    buds.log = { dir, text in
        let arrow = switch dir { case .sent: "-> "; case .received: "<- "; case .info: "" }
        print(stamp() + arrow + text); fflush(stdout)
    }
    buds.onHostsChange = { hosts in
        print(stamp() + "HOSTS " + hosts.map { "\($0.name) connected=\($0.connected) self=\($0.isThisMac)" }
            .joined(separator: " | ")); fflush(stdout)
    }
    buds.start()
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
    RunLoop.main.run()
} else if let i = args.firstIndex(of: "--raw") {
    // Sends each "CMD:PAYLOAD" (hex) argument 2.5 s apart and logs every packet.
    let started = Date()
    let buds = BudsController()
    buds.log = { dir, text in
        let arrow = switch dir { case .sent: "-> "; case .received: "<- "; case .info: "" }
        print(String(format: "[%6.2fs] ", Date().timeIntervalSince(started)) + arrow + text); fflush(stdout)
    }
    buds.start()
    let commands = args[(i + 1)...].map { $0.split(separator: ":", omittingEmptySubsequences: false).map(String.init) }
    for (n, parts) in commands.enumerated() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4 + Double(n) * 2.5) {
            let digits = Array(parts.count > 1 ? parts[1] : "")
            let payload = stride(from: 0, to: digits.count - 1, by: 2).compactMap { UInt8(String(digits[$0...$0 + 1]), radix: 16) }
            buds.sendRaw(command: UInt16(parts[0], radix: 16) ?? 0, payload: payload)
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 6 + Double(commands.count) * 2.5) { exit(0) }
    RunLoop.main.run()
} else if let i = args.firstIndex(of: "--cli") {
    // Command-line mode for debugging and scripting, e.g.:
    //   BudsControl.app/Contents/MacOS/BudsControl --cli status
    //   BudsControl.app/Contents/MacOS/BudsControl --cli anc|transparency|off|smart|max|moderate|mild
    let action = args.count > i + 1 ? args[i + 1] : "status"
    let buds = BudsController()
    let started = Date()
    buds.log = { dir, text in
        let arrow = switch dir { case .sent: "-> "; case .received: "<- "; case .info: "" }
        print(String(format: "[%5.0fms] ", Date().timeIntervalSince(started) * 1000) + arrow + text)
    }

    // Like a shortcut press: request the mode right away, before the link is even up.
    if let mode = NoiseMode(rawValue: action) {
        buds.setMode(mode)
    } else if let level = ANCLevel(rawValue: action) {
        buds.setMode(.anc, level: level)
    }
    buds.start()

    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        print("device:  \(buds.deviceName) [\(buds.productID ?? "?")] \(buds.link)")
        print("mode:    \(buds.mode?.rawValue ?? "unknown")\(buds.level.map { " (\($0.rawValue))" } ?? "")")
        print("battery: L \(buds.left?.level ?? -1)%  R \(buds.right?.level ?? -1)%  case \(buds.caseBattery?.level ?? -1)%")
        exit(buds.link == .connected ? 0 : 1)
    }
    RunLoop.main.run()
} else {
    BudsControlApp.main()
}
