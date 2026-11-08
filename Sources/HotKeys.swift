import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A key combination, stored in UserDefaults.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt  // NSEvent.ModifierFlags raw value

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    var display: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    static func keyName(_ code: UInt32) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
            kVK_F19: "F19", kVK_F20: "F20",
        ]
        if let name = special[Int(code)] { return name }
        // Translate through the current keyboard layout so e.g. AZERTY shows the right letter.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String in
            let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var len = 0
            UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &chars)
            return String(utf16CodeUnits: chars, count: len).uppercased()
        }
    }

    static func isFunctionKey(_ code: UInt16) -> Bool {
        [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
         kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20].contains(Int(code))
    }
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case cycle, anc, transparency, off
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cycle: "Cycle modes"
        case .anc: "Noise Cancellation"
        case .transparency: "Transparency"
        case .off: "Off"
        }
    }

    var symbol: String {
        switch self {
        case .cycle: "arrow.triangle.2.circlepath"
        case .anc: NoiseMode.anc.symbol
        case .transparency: NoiseMode.transparency.symbol
        case .off: NoiseMode.off.symbol
        }
    }
}

/// System-wide hotkeys via Carbon's RegisterEventHotKey, which needs no Accessibility permission.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var handlerInstalled = false

    /// Returns false if the combination is already taken by another app.
    @discardableResult
    func register(id: UInt32, shortcut: Shortcut, action: @escaping () -> Void) -> Bool {
        unregister(id: id)
        installHandler()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4255_4453), id: id)  // 'BUDS'
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        handlers[id] = action
        return true
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers[id] = nil
    }

    func unregisterAll() {
        refs.keys.forEach { unregister(id: $0) }
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            DispatchQueue.main.async { HotKeyCenter.shared.handlers[hotKeyID.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// Click, then press a key combination. Esc cancels, ⌫ clears.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    var onRecordingChange: (Bool) -> Void = { _ in }

    @StateObject private var state = RecorderState()
    private var recording: Bool { state.recording }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Type shortcut…" : (shortcut?.display ?? "Record Shortcut"))
                    .font(shortcut == nil || recording ? .callout : .callout.monospaced())
                    .foregroundStyle(recording ? Color.accentColor : (shortcut == nil ? .secondary : .primary))
                    .frame(minWidth: 120)
            }
            .buttonStyle(.glass)

            if shortcut != nil && !recording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("Clear shortcut")
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        state.recording = true
        onRecordingChange(true)
        state.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            switch Int(event.keyCode) {
            case kVK_Escape where mods.isEmpty:
                stop()
            case kVK_Delete where mods.isEmpty:
                shortcut = nil
                stop()
            default:
                if mods.isEmpty && !Shortcut.isFunctionKey(event.keyCode) {
                    NSSound.beep()  // needs a modifier, or it would steal a plain key everywhere
                } else {
                    shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: mods.rawValue)
                    stop()
                }
            }
            return nil
        }
    }

    private func stop() {
        if let monitor = state.monitor { NSEvent.removeMonitor(monitor) }
        state.monitor = nil
        if recording { onRecordingChange(false) }
        state.recording = false
    }
}

private final class RecorderState: ObservableObject {
    @Published var recording = false
    var monitor: Any?
}
