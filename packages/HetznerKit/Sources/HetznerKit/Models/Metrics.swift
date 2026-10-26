import Foundation

public enum MetricType: String, Sendable, CaseIterable {
    case cpu, disk, network
}

public enum MetricSeries {
    public static let cpu = "cpu"
    public static let diskIOPSRead = "disk.0.iops.read"
    public static let diskIOPSWrite = "disk.0.iops.write"
    public static let diskBandwidthRead = "disk.0.bandwidth.read"
    public static let diskBandwidthWrite = "disk.0.bandwidth.write"
    public static let networkPPSIn = "network.0.pps.in"
    public static let networkPPSOut = "network.0.pps.out"
    public static let networkBandwidthIn = "network.0.bandwidth.in"
    public static let networkBandwidthOut = "network.0.bandwidth.out"
}

public struct MetricPoint: Sendable, Hashable {
    public let time: Date
    public let value: Double

    public init(time: Date, value: Double) {
        self.time = time
        self.value = value
    }
}

public struct ServerMetrics: Sendable, Hashable, Decodable {
    public let start: Date
    public let end: Date
    public let step: Double
    public let series: [String: [MetricPoint]]

    public init(start: Date, end: Date, step: Double, series: [String: [MetricPoint]]) {
        self.start = start
        self.end = end
        self.step = step
        self.series = series
    }

    enum CodingKeys: String, CodingKey {
        case start, end, step
        case timeSeries = "time_series"
    }

    private struct Series: Decodable {
        let values: [Sample]
    }

    private struct Sample: Decodable {
        let point: MetricPoint?

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let timestamp = try container.decode(Double.self)
            let text = try container.decode(String.self)
            if let value = Double(text), value.isFinite {
                point = MetricPoint(time: Date(timeIntervalSince1970: timestamp), value: value)
            } else {
                point = nil
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decode(Date.self, forKey: .start)
        end = try container.decode(Date.self, forKey: .end)
        step = try container.decode(Double.self, forKey: .step)
        let raw = try container.decode([String: Series].self, forKey: .timeSeries)
        series = raw.mapValues { $0.values.compactMap(\.point) }
    }

    public func points(_ name: String) -> [MetricPoint] {
        series[name] ?? []
    }

    public func cpuPercent(cores: Double) -> [MetricPoint] {
        let divisor = max(cores, 1)
        return points(MetricSeries.cpu).map { MetricPoint(time: $0.time, value: $0.value / divisor) }
    }

    public var totalIOPS: [MetricPoint] {
        Self.sum(points(MetricSeries.diskIOPSRead), points(MetricSeries.diskIOPSWrite))
    }

    static func sum(_ a: [MetricPoint], _ b: [MetricPoint]) -> [MetricPoint] {
        let other = Dictionary(b.map { ($0.time, $0.value) }, uniquingKeysWith: { first, _ in first })
        return a.map { MetricPoint(time: $0.time, value: $0.value + (other[$0.time] ?? 0)) }
    }
}
