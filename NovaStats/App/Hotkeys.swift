import AppKit
import Carbon

// system-wide shortcuts. carbon hotkeys need no accessibility permission
final class Hotkeys {
    static let shared = Hotkeys()

    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    func register() {
        pause()
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                DispatchQueue.main.async { Hotkeys.shared.pressed(id.id) }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        add(Prefs.shared.dashboardShortcut, 1)
        add(Prefs.shared.hudShortcut, 2)
    }

    // while a new shortcut is being typed in settings
    func pause() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }

    private func add(_ shortcut: Shortcut?, _ id: UInt32) {
        guard let shortcut else { return }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: 0x4E535453, id: id) // "NSTS"
        if RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr,
           let ref {
            refs.append(ref)
        }
    }

    private func pressed(_ id: UInt32) {
        switch id {
        case 1: Windows.shared.toggleDashboard()
        case 2: Prefs.shared.showHUD.toggle()
        default: break
        }
    }

    static func carbon(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    static func label(_ flags: NSEvent.ModifierFlags, _ event: NSEvent) -> String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        let names: [UInt16: String] = [49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        return text + (names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "?")
    }
}
