import Foundation

public struct RateLimit: Sendable, Equatable, Codable {
    public let limit: Int
    public let remaining: Int
    public let resetAt: Date

    public init(limit: Int, remaining: Int, resetAt: Date) {
        self.limit = limit
        self.remaining = remaining
        self.resetAt = resetAt
    }

    init?(headers: HTTPURLResponse) {
        guard
            let limit = headers.value(forHTTPHeaderField: "RateLimit-Limit").flatMap(Int.init),
            let remaining = headers.value(forHTTPHeaderField: "RateLimit-Remaining").flatMap(Int.init),
            let reset = headers.value(forHTTPHeaderField: "RateLimit-Reset").flatMap(TimeInterval.init)
        else { return nil }
        self.init(limit: limit, remaining: remaining, resetAt: Date(timeIntervalSince1970: reset))
    }

    public var usedFraction: Double {
        guard limit > 0 else { return 0 }
        return Double(limit - remaining) / Double(limit)
    }

    public func isExhausted(at now: Date) -> Bool {
        remaining <= 0 && now < resetAt
    }
}
