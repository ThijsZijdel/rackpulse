import Foundation

public enum UptimeState: Int, Sendable, Codable, Comparable {
    case up, off, alert, down

    public static func < (lhs: UptimeState, rhs: UptimeState) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct UptimeHistory: Sendable, Codable, Equatable {
    public static let retention: TimeInterval = 31 * 86_400

    public private(set) var hours: [Int64: [Int: UptimeState]]

    public init(hours: [Int64: [Int: UptimeState]] = [:]) {
        self.hours = hours
    }

    static func hour(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 / 3_600).rounded(.down))
    }

    @discardableResult
    public mutating func record(_ id: Int64, _ state: UptimeState, at date: Date) -> Bool {
        let hour = Self.hour(date)
        var series = hours[id] ?? [:]
        let previous = series[hour]
        series[hour] = max(previous ?? state, state)
        let oldest = Self.hour(date.addingTimeInterval(-Self.retention))
        series = series.filter { $0.key >= oldest }
        hours[id] = series
        return previous != series[hour]
    }

    public mutating func keep(only ids: Set<Int64>) {
        hours = hours.filter { ids.contains($0.key) }
    }

    public func hourly(_ id: Int64, endingAt date: Date, count: Int = 24) -> [UptimeState?] {
        let last = Self.hour(date)
        let series = hours[id] ?? [:]
        return (0..<count).map { series[last - count + 1 + $0] }
    }

    public func daily(_ id: Int64, endingAt date: Date, count: Int = 30, calendar: Calendar = .current) -> [UptimeState?] {
        let series = hours[id] ?? [:]
        let today = calendar.startOfDay(for: date)
        return (0..<count).map { offset in
            guard let start = calendar.date(byAdding: .day, value: offset - count + 1, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return (Self.hour(start)..<Self.hour(end)).compactMap { series[$0] }.max()
        }
    }
}
