import Foundation

public struct Price: Sendable, Hashable, Decodable {
    public let net: Decimal
    public let gross: Decimal

    public init(net: Decimal, gross: Decimal) {
        self.net = net
        self.gross = gross
    }

    enum CodingKeys: String, CodingKey {
        case net, gross
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        net = try container.decodeDecimalString(forKey: .net)
        gross = try container.decodeDecimalString(forKey: .gross)
    }

    public func value(_ kind: PriceKind) -> Decimal {
        switch kind {
        case .net: net
        case .gross: gross
        }
    }
}

public enum PriceKind: String, Sendable, Codable, CaseIterable {
    case net
    case gross
}

public struct LocationPrice: Sendable, Hashable, Decodable {
    public let location: String
    public let priceHourly: Price?
    public let priceMonthly: Price
    public let includedTraffic: Int64?

    public init(location: String, priceHourly: Price?, priceMonthly: Price, includedTraffic: Int64? = nil) {
        self.location = location
        self.priceHourly = priceHourly
        self.priceMonthly = priceMonthly
        self.includedTraffic = includedTraffic
    }

    enum CodingKeys: String, CodingKey {
        case location
        case priceHourly = "price_hourly"
        case priceMonthly = "price_monthly"
        case includedTraffic = "included_traffic"
    }
}

extension Array where Element == LocationPrice {
    public func price(at location: String) -> LocationPrice? {
        first { $0.location == location }
    }
}

public struct Location: Sendable, Hashable, Decodable {
    public let id: Int64
    public let name: String
    public let description: String
    public let city: String
    public let country: String

    public init(id: Int64, name: String, description: String = "", city: String = "", country: String = "") {
        self.id = id
        self.name = name
        self.description = description
        self.city = city
        self.country = country
    }
}
