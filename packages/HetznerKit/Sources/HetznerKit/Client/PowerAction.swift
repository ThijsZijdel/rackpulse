import Foundation

public enum PowerAction: String, Sendable, CaseIterable, Identifiable {
    case start = "poweron"
    case shutdown
    case reboot
    case powerOff = "poweroff"
    case reset

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .start: "Start"
        case .shutdown: "Shut Down"
        case .reboot: "Reboot"
        case .powerOff: "Power Off"
        case .reset: "Reset"
        }
    }

    public var detail: String {
        switch self {
        case .start: "Powers the server on."
        case .shutdown: "Asks the OS to shut down cleanly."
        case .reboot: "Asks the OS to restart cleanly."
        case .powerOff: "Cuts power at once, like pulling the plug. Unsaved data can be lost."
        case .reset: "Hard restart, like pressing the reset button. Unsaved data can be lost."
        }
    }

    public var isDestructive: Bool {
        self == .powerOff || self == .reset
    }

    public static func available(for status: ServerStatus) -> [PowerAction] {
        switch status {
        case .running: [.shutdown, .reboot, .powerOff, .reset]
        case .off: [.start]
        default: []
        }
    }

    public func path(server id: Int64) -> String {
        "/servers/\(id)/actions/\(rawValue)"
    }

    static func allows(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        return parts.count == 4
            && parts[0] == "servers"
            && Int64(parts[1]) != nil
            && parts[2] == "actions"
            && PowerAction(rawValue: String(parts[3])) != nil
    }
}
