import Foundation

public enum UptimeSource: String, Sendable, Hashable, Comparable {
    case hetzner, rackpulse, agent

    private var rank: Int {
        switch self {
        case .hetzner: 0
        case .rackpulse: 1
        case .agent: 2
        }
    }

    public static func < (lhs: UptimeSource, rhs: UptimeSource) -> Bool { lhs.rank < rhs.rank }
}

public struct UptimeEntry: Sendable, Hashable {
    public let state: UptimeState
    public let source: UptimeSource
    public let minutes: (running: Int, expected: Int)?

    public init(_ state: UptimeState, _ source: UptimeSource, minutes: (running: Int, expected: Int)? = nil) {
        self.state = state
        self.source = source
        self.minutes = minutes
    }

    public static func == (lhs: UptimeEntry, rhs: UptimeEntry) -> Bool {
        lhs.state == rhs.state && lhs.source == rhs.source
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(state)
        hasher.combine(source)
    }
}

public struct UptimeTimeline: Sendable {
    public static let window: TimeInterval = 31 * 86_400
    static let onCommands: Set<String> = ["create_server", "start_server", "reboot_server", "reset_server", "rebuild_server"]
    static let offCommands: Set<String> = ["stop_server", "shutdown_server"]
    static let plannedRestarts: Set<String> = ["reboot_server", "reset_server", "rebuild_server", "change_server_type"]
    static let tolerance = 2
    static let plannedTolerance = 15

    public private(set) var hours: [Int: UptimeEntry] = [:]

    public init(
        created: Date,
        status: ServerStatus,
        local: [Int: UptimeState],
        agent: AgentUptime?,
        actions: [ServerAction],
        actionsComplete: Bool,
        now: Date
    ) {
        let windowStart = now.addingTimeInterval(-Self.window)
        let off = Self.offIntervals(status: status, actions: actions, windowStart: windowStart, now: now)
        let planned = Set(actions.filter { Self.plannedRestarts.contains($0.command) }.map { UptimeHistory.hour($0.started) })
        let first = UptimeHistory.hour(max(created, windowStart))
        let last = UptimeHistory.hour(now)
        guard first <= last else { return }

        for hour in first...last {
            let start = max(Date(timeIntervalSince1970: Double(hour) * 3_600), created)
            let end = min(Date(timeIntervalSince1970: Double(hour + 1) * 3_600), now)
            guard end > start else { continue }
            let offMinutes = Self.overlap(off, start, end)

            if let agent, let entry = Self.fromAgent(
                agent, hour: hour, start: start, end: end, offMinutes: offMinutes,
                planned: planned.contains(hour), local: local[hour]
            ) {
                hours[hour] = entry
            } else if let state = local[hour] {
                hours[hour] = UptimeEntry(state, .rackpulse)
            } else if actionsComplete {
                hours[hour] = UptimeEntry(offMinutes >= 1 ? .off : .up, .hetzner)
            }
        }
    }

    public func hourly(endingAt date: Date, count: Int = 24) -> [UptimeEntry?] {
        let last = UptimeHistory.hour(date)
        return (0..<count).map { hours[last - count + 1 + $0] }
    }

    public func daily(endingAt date: Date, count: Int = 30, calendar: Calendar = .current) -> [UptimeEntry?] {
        let today = calendar.startOfDay(for: date)
        return (0..<count).map { offset in
            guard let start = calendar.date(byAdding: .day, value: offset - count + 1, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            let entries = (UptimeHistory.hour(start)..<UptimeHistory.hour(end)).compactMap { hours[$0] }
            guard let state = entries.map(\.state).max(), let source = entries.map(\.source).max() else { return nil }
            return UptimeEntry(state, source)
        }
    }

    public var sources: Set<UptimeSource> { Set(hours.values.map(\.source)) }

    static func fromAgent(
        _ agent: AgentUptime,
        hour: Int,
        start: Date,
        end: Date,
        offMinutes: Double,
        planned: Bool,
        local: UptimeState?
    ) -> UptimeEntry? {
        let covered = max(start, agent.coverageStart)
        let until = min(end, agent.asOf)
        guard until.timeIntervalSince(covered) >= 5 * 60 else { return nil }
        let expected = until.timeIntervalSince(covered) / 60 - offMinutes
        let running = Double(agent.hours[Int64(hour) * 3_600] ?? 0)
        let missing = expected - running
        let allowed = Double(planned ? plannedTolerance : tolerance) + (until < end ? 1 : 0)
        let state: UptimeState
        if expected < 1 {
            state = .off
        } else if missing > allowed {
            state = .down
        } else if offMinutes >= 1 {
            state = .off
        } else {
            state = local == .alert ? .alert : .up
        }
        let shown = (running: Int(min(running, expected.rounded())), expected: Int(expected.rounded()))
        return UptimeEntry(state, .agent, minutes: expected >= 1 ? shown : nil)
    }

    static func offIntervals(status: ServerStatus, actions: [ServerAction], windowStart: Date, now: Date) -> [(Date, Date)] {
        let power = actions
            .filter { $0.status == "success" && (onCommands.contains($0.command) || offCommands.contains($0.command)) }
            .sorted { $0.started < $1.started }
        let isOff: Bool
        if let firstInWindow = power.first(where: { $0.started >= windowStart }) {
            let before = power.last { $0.started < windowStart }
            isOff = before.map { offCommands.contains($0.command) } ?? onCommands.contains(firstInWindow.command)
        } else {
            isOff = power.last.map { offCommands.contains($0.command) } ?? (status == .off)
        }
        var intervals: [(Date, Date)] = []
        var offSince: Date? = isOff ? windowStart : nil
        for action in power where action.started >= windowStart {
            if offCommands.contains(action.command), offSince == nil {
                offSince = action.finished ?? action.started
            } else if onCommands.contains(action.command), let since = offSince {
                intervals.append((since, action.started))
                offSince = nil
            }
        }
        if let since = offSince { intervals.append((since, now)) }
        return intervals
    }

    static func overlap(_ intervals: [(Date, Date)], _ start: Date, _ end: Date) -> Double {
        intervals.reduce(0) { total, interval in
            let from = max(interval.0, start)
            let to = min(interval.1, end)
            return total + max(0, to.timeIntervalSince(from)) / 60
        }
    }
}

extension UptimeHistory {
    public func series(_ id: Int64) -> [Int: UptimeState] {
        hours[id] ?? [:]
    }
}
