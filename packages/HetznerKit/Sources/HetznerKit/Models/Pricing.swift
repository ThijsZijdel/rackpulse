import Foundation

public struct Pricing: Sendable, Hashable, Decodable {
    public let currency: String
    public let vatRate: Decimal
    public let primaryIps: [IPPricing]
    public let floatingIps: [IPPricing]
    public let volumePerGBMonth: Price
    public let serverBackupPercentage: Decimal
    public let serverTypes: [TypePricing]
    public let loadBalancerTypes: [TypePricing]

    public init(
        currency: String,
        vatRate: Decimal,
        primaryIps: [IPPricing],
        floatingIps: [IPPricing],
        volumePerGBMonth: Price,
        serverBackupPercentage: Decimal,
        serverTypes: [TypePricing] = [],
        loadBalancerTypes: [TypePricing] = []
    ) {
        self.currency = currency
        self.vatRate = vatRate
        self.primaryIps = primaryIps
        self.floatingIps = floatingIps
        self.volumePerGBMonth = volumePerGBMonth
        self.serverBackupPercentage = serverBackupPercentage
        self.serverTypes = serverTypes
        self.loadBalancerTypes = loadBalancerTypes
    }

    enum CodingKeys: String, CodingKey {
        case currency, volume
        case vatRate = "vat_rate"
        case primaryIps = "primary_ips"
        case floatingIps = "floating_ips"
        case serverBackup = "server_backup"
        case serverTypes = "server_types"
        case loadBalancerTypes = "load_balancer_types"
    }

    private struct VolumePricing: Decodable {
        let pricePerGBMonth: Price

        enum CodingKeys: String, CodingKey {
            case pricePerGBMonth = "price_per_gb_month"
        }
    }

    private struct BackupPricing: Decodable {
        let percentage: Decimal

        enum CodingKeys: String, CodingKey {
            case percentage
        }

        init(from decoder: Decoder) throws {
            percentage = try decoder.container(keyedBy: CodingKeys.self).decodeDecimalString(forKey: .percentage)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currency = try container.decode(String.self, forKey: .currency)
        vatRate = try container.decodeDecimalString(forKey: .vatRate)
        primaryIps = try container.decode([IPPricing].self, forKey: .primaryIps)
        floatingIps = try container.decode([IPPricing].self, forKey: .floatingIps)
        volumePerGBMonth = try container.decode(VolumePricing.self, forKey: .volume).pricePerGBMonth
        serverBackupPercentage = try container.decode(BackupPricing.self, forKey: .serverBackup).percentage
        serverTypes = try container.decode([TypePricing].self, forKey: .serverTypes)
        loadBalancerTypes = try container.decode([TypePricing].self, forKey: .loadBalancerTypes)
    }

    public struct IPPricing: Sendable, Hashable, Decodable {
        public let type: IPType
        public let prices: [LocationPrice]

        public init(type: IPType, prices: [LocationPrice]) {
            self.type = type
            self.prices = prices
        }
    }

    public struct TypePricing: Sendable, Hashable, Decodable {
        public let id: Int64
        public let name: String
        public let prices: [LocationPrice]

        public init(id: Int64, name: String, prices: [LocationPrice]) {
            self.id = id
            self.name = name
            self.prices = prices
        }
    }

    public func primaryIP(_ type: IPType, at location: String) -> LocationPrice? {
        primaryIps.first { $0.type == type }?.prices.price(at: location)
    }

    public func floatingIP(_ type: IPType, at location: String) -> LocationPrice? {
        floatingIps.first { $0.type == type }?.prices.price(at: location)
    }
}
