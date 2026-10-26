import Carbon.HIToolbox
import Foundation

enum PanelShortcut: String, Codable, CaseIterable, Identifiable {
    case off, controlOptionR, controlOptionSpace, optionCommandR

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .controlOptionR: "⌃⌥R"
        case .controlOptionSpace: "⌃⌥Space"
        case .optionCommandR: "⌥⌘R"
        }
    }

    var carbon: (key: UInt32, modifiers: UInt32)? {
        switch self {
        case .off: nil
        case .controlOptionR: (UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey))
        case .controlOptionSpace: (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        case .optionCommandR: (UInt32(kVK_ANSI_R), UInt32(optionKey | cmdKey))
        }
    }
}

@MainActor
final class GlobalShortcut {
    static var action: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var installed = false

    func apply(_ shortcut: PanelShortcut) {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        guard let carbon = shortcut.carbon else { return }
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { GlobalShortcut.action?() }
                }
                return noErr
            }, 1, &spec, nil, nil)
            installed = true
        }
        let id = EventHotKeyID(signature: OSType(0x5242_4152), id: 1)
        RegisterEventHotKey(carbon.key, carbon.modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
    }
}
