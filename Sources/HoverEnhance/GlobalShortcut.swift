import AppKit
import Carbon.HIToolbox

/// A key combination, as recorded in Settings.
struct Shortcut: Codable, Hashable, Sendable {
    /// The key's virtual key code, as `NSEvent.keyCode` gives it.
    let keyCode: UInt16
    /// Command, Option, Control, and Shift, as `NSEvent.ModifierFlags` raw values.
    let modifiers: UInt
    /// The key as shown: "P", "F5", "Space".
    let key: String

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// "⌃⌥⌘P", in the order macOS menus use.
    var label: String {
        let flags = modifierFlags
        return (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "")
            + (flags.contains(.command) ? "⌘" : "") + key
    }

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection([.command, .option, .control, .shift]).rawValue
        self.key = key
    }

    /// The key pressed, if it makes a shortcut: one with ⌘, ⌥, or ⌃, so typing can't set it off.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.isDisjoint(with: [.command, .option, .control]) else { return nil }
        let key = Self.keyNames[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
        guard !key.isEmpty, !key.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        self.init(keyCode: event.keyCode, modifiers: flags, key: key)
    }

    /// Keys whose characters don't name them.
    private static let keyNames: [UInt16: String] = [
        UInt16(kVK_Space): "Space", UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥", UInt16(kVK_Delete): "⌫",
        UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
        UInt16(kVK_DownArrow): "↓", UInt16(kVK_UpArrow): "↑", UInt16(kVK_Home): "↖", UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞", UInt16(kVK_PageDown): "⇟",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5",
        UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
    ]

    fileprivate var carbonModifiers: UInt32 {
        let flags = modifierFlags
        var carbon = 0
        if flags.contains(.command) { carbon |= cmdKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        return UInt32(carbon)
    }
}

/// A shortcut that works whichever app is in front. A Carbon hot key: it needs no permission beyond
/// what the app has, and the keys go to HoverEnhance alone rather than to the app in front too.
@MainActor
final class GlobalShortcut {
    var action: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// Replaces the shortcut, or removes it when nil. False if the system wouldn't take it, as when
    /// another app holds the same keys.
    @discardableResult
    func register(_ shortcut: Shortcut?) -> Bool {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        guard let shortcut else { return true }
        installHandler()
        let id = EventHotKeyID(signature: OSType(0x4845_4E48), id: 1) // "HENH"
        return RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers, id, GetEventDispatcherTarget(), 0, &hotKey) == noErr
    }

    private func installHandler() {
        guard handler == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // Hot keys arrive on the main thread, through the main event loop.
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { shortcut.action?() }
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
}
