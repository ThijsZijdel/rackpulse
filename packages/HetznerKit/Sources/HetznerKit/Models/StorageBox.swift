import Foundation

public struct StorageBox: Sendable, Hashable, Decodable, Identifiable {
    public let id: Int64
    public let name: String
    public let status: String
    public let created: Date
    public let location: Location
    public let storageBoxType: BoxType
    public let stats: Stats
    public let labels: [String: String]

    public init(
        id: Int64,
        name: String,
        status: String = "active",
        created: Date,
        location: Location,
        storageBoxType: BoxType,
        stats: Stats,
        labels: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.created = created
        self.location = location
        self.storageBoxType = storageBoxType
        self.stats = stats
        self.labels = labels
    }

    enum CodingKeys: String, CodingKey {
        case id, name, status, created, location, stats, labels
        case storageBoxType = "storage_box_type"
    }

    public struct BoxType: Sendable, Hashable, Decodable {
        public let id: Int64
        public let name: String
        public let description: String
        public let size: Int64
        public let prices: [LocationPrice]

        public init(id: Int64, name: String, description: String, size: Int64, prices: [LocationPrice]) {
            self.id = id
            self.name = name
            self.description = description
            self.size = size
            self.prices = prices
        }
    }

    public struct Stats: Sendable, Hashable, Decodable {
        public let size: Int64
        public let sizeData: Int64
        public let sizeSnapshots: Int64

        public init(size: Int64, sizeData: Int64, sizeSnapshots: Int64) {
            self.size = size
            self.sizeData = sizeData
            self.sizeSnapshots = sizeSnapshots
        }

        enum CodingKeys: String, CodingKey {
            case size
            case sizeData = "size_data"
            case sizeSnapshots = "size_snapshots"
        }
    }

    public var capacity: Int64 { storageBoxType.size }

    public var usedFraction: Double {
        guard capacity > 0 else { return 0 }
        return Double(stats.size) / Double(capacity)
    }

    public var freeBytes: Int64 { max(0, capacity - stats.size) }
}
