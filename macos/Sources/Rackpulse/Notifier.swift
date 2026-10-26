import AppKit
import HetznerKit
import UserNotifications

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private static let category = "alert"
    private static let snoozeAction = "snooze"
    private static let openAction = "open"

    var onSnooze: ((UUID, String) -> Void)?
    var onOpen: (() -> Void)?
    private var requested = false

    func setUp() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze 24 h")
        let open = UNNotificationAction(identifier: Self.openAction, title: "Open", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [snooze, open], intentIdentifiers: [])
        ])
    }

    func requestAuthorization() {
        guard !requested else { return }
        requested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func preview(_ kind: RuleKind, project: Project) {
        requestAuthorization()
        let titles: [RuleKind: String] = [
            .serverDown: "web-1 is off",
            .sustainedCPU: "web-1 CPU above 85% for 10 min",
            .storageBox: "backups is 91% full",
            .trafficQuota: "web-1 used 82% of its included traffic",
            .diskIO: "db-1 disk I/O above 3× its 7-day median",
            .budget: "Forecast is above your monthly budget",
            .unexpectedChange: "New server web-2",
            .diskSpace: "web-1: / is 92% full",
            .memory: "web-1 memory above 90% for 10 min",
            .container: "web-1: app-worker restarted 14 times in the last hour",
            .failedService: "web-1: nginx.service failed",
            .rebootRequired: "web-1 needs a reboot to finish updates",
            .agentUnreachable: "web-1 is running, but its agent does not answer",
        ]
        let severity: Severity = switch kind {
        case .serverDown, .storageBox: .critical
        case .budget, .unexpectedChange, .rebootRequired: .info
        default: .warning
        }
        let alert = FiringAlert(id: "preview:\(kind.rawValue):\(UUID().uuidString)", kind: kind, severity: severity,
                                title: titles[kind] ?? kind.title, since: .now)
        post(alert, project: project)
    }

    func post(_ alert: FiringAlert, project: Project, environment: ServerEnvironment = .none) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.subtitle = environment.badge.map { "\(project.name) · \($0)" } ?? project.name
        content.body = "Started \(alert.since.formatted(date: .omitted, time: .shortened)). Rule: \(alert.kind.title)."
        content.sound = alert.severity == .critical ? .defaultCritical : .default
        content.categoryIdentifier = Self.category
        content.userInfo = ["project": project.id.uuidString, "alert": alert.id]
        let request = UNNotificationRequest(identifier: "\(project.id.uuidString)|\(alert.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        guard let project = (info["project"] as? String).flatMap(UUID.init), let alert = info["alert"] as? String else { return }
        await MainActor.run {
            if action == Self.snoozeAction {
                onSnooze?(project, alert)
            } else {
                onOpen?()
            }
        }
    }
}

extension RuleKind {
    var title: String {
        switch self {
        case .serverDown: "Server down"
        case .sustainedCPU: "Sustained CPU"
        case .storageBox: "Storage Box filling"
        case .trafficQuota: "Traffic quota"
        case .diskIO: "Disk I/O anomaly"
        case .budget: "Budget"
        case .unexpectedChange: "Unexpected change"
        case .diskSpace: "Disk space"
        case .memory: "Memory"
        case .container: "Docker containers"
        case .failedService: "Failed service"
        case .rebootRequired: "Reboot required"
        case .agentUnreachable: "Agent not answering"
        }
    }

    var summary: String {
        switch self {
        case .serverDown: "A server is not running and you did not stop it."
        case .sustainedCPU: "CPU stays above the threshold for the whole period."
        case .storageBox: "A Storage Box is above the threshold, or the forecast says it will be full soon."
        case .trafficQuota: "Outgoing traffic passes this share of the included traffic."
        case .diskIO: "Disk IOPS stay above a multiple of the 7-day median."
        case .budget: "The month's cost forecast goes above the project's budget."
        case .unexpectedChange: "A server or volume appears or disappears, a server is rebuilt, or a firewall changes."
        case .diskSpace: "A file system passes this share of its space or inodes, or turns read-only."
        case .memory: "Memory use stays above the threshold for the whole period."
        case .container: "A container is unhealthy, keeps restarting, or stopped with an error in the last hour."
        case .failedService: "A systemd service on the server is in the failed state."
        case .rebootRequired: "The server installed updates that need a reboot."
        case .agentUnreachable: "Hetzner says the server is running, but the agent stops answering. The server may be frozen or out of memory."
        }
    }
}
