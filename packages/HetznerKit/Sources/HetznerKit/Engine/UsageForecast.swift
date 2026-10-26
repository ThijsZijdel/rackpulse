import Foundation

public struct UsageSample: Sendable, Hashable, Codable {
    public let time: Date
    public let used: Double

    public init(time: Date, used: Double) {
        self.time = time
        self.used = used
    }
}

public struct UsageForecast: Sendable, Hashable {
    public let growthPerDay: Double
    public let daysUntilFull: Double

    public static func fit(
        _ samples: [UsageSample],
        capacity: Double,
        minSamples: Int = 6,
        minSpan: TimeInterval = 6 * 3600
    ) -> UsageForecast? {
        let sorted = samples.sorted { $0.time < $1.time }
        guard
            sorted.count >= minSamples,
            let first = sorted.first,
            let last = sorted.last,
            last.time.timeIntervalSince(first.time) >= minSpan
        else { return nil }

        let xs = sorted.map { $0.time.timeIntervalSince(first.time) }
        let ys = sorted.map(\.used)
        let n = Double(sorted.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var covariance = 0.0
        var variance = 0.0
        for (x, y) in zip(xs, ys) {
            covariance += (x - meanX) * (y - meanY)
            variance += (x - meanX) * (x - meanX)
        }
        guard variance > 0 else { return nil }
        let slope = covariance / variance
        guard slope > 0 else { return nil }
        let intercept = meanY - slope * meanX
        let fullAt = (capacity - intercept) / slope
        let remaining = max(0, fullAt - xs[xs.count - 1])
        return UsageForecast(growthPerDay: slope * 86_400, daysUntilFull: remaining / 86_400)
    }
}
