import Foundation

public struct UsageHistory: Sendable, Codable, Equatable {
    public static let interval: TimeInterval = 3_600
    public static let retention: TimeInterval = 45 * 86_400

    public private(set) var samples: [Int64: [UsageSample]]

    public init(samples: [Int64: [UsageSample]] = [:]) {
        self.samples = samples
    }

    @discardableResult
    public mutating func record(_ id: Int64, used: Double, at time: Date) -> Bool {
        var series = samples[id] ?? []
        if let last = series.last, time.timeIntervalSince(last.time) < Self.interval - 60 { return false }
        series.append(UsageSample(time: time, used: used))
        series.removeAll { time.timeIntervalSince($0.time) > Self.retention }
        samples[id] = series
        return true
    }

    public mutating func keep(only ids: Set<Int64>) {
        samples = samples.filter { ids.contains($0.key) }
    }

    public func forecast(_ id: Int64, capacity: Double) -> UsageForecast? {
        UsageForecast.fit(samples[id] ?? [], capacity: capacity)
    }

    public func span(_ id: Int64) -> TimeInterval {
        guard let series = samples[id], let first = series.first, let last = series.last else { return 0 }
        return last.time.timeIntervalSince(first.time)
    }
}
