import Foundation

public struct Volume: Sendable, Hashable, Decodable, Identifiable {
    public let id: Int64
    public let name: String
    public let created: Date
    public let server: Int64?
    public let location: Location
    public let size: Double
    public let status: String
    public let format: String?
    public let labels: [String: String]

    public init(
        id: Int64,
        name: String,
        created: Date,
        server: Int64?,
        location: Location,
        size: Double,
        status: String = "available",
        format: String? = nil,
        labels: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.created = created
        self.server = server
        self.location = location
        self.size = size
        self.status = status
        self.format = format
        self.labels = labels
    }
}

public struct ServerAction: Sendable, Hashable, Decodable, Identifiable {
    public let id: Int64
    public let command: String
    public let status: String
    public let started: Date
    public let finished: Date?
    public let resources: [ResourceRef]
    public let error: ActionError?

    public init(
        id: Int64,
        command: String,
        status: String = "success",
        started: Date,
        finished: Date? = nil,
        resources: [ResourceRef],
        error: ActionError? = nil
    ) {
        self.id = id
        self.command = command
        self.status = status
        self.started = started
        self.finished = finished
        self.resources = resources
        self.error = error
    }

    public struct ResourceRef: Sendable, Hashable, Decodable {
        public let id: Int64
        public let type: String

        public init(id: Int64, type: String) {
            self.id = id
            self.type = type
        }
    }

    public struct ActionError: Sendable, Hashable, Decodable {
        public let code: String
        public let message: String
    }

    public func targets(server id: Int64) -> Bool {
        resources.contains { $0.type == "server" && $0.id == id }
    }
}

public struct Firewall: Sendable, Hashable, Decodable, Identifiable {
    public let id: Int64
    public let name: String
    public let created: Date
    public let rules: [Rule]
    public let appliedTo: [AppliedTo]

    public init(id: Int64, name: String, created: Date, rules: [Rule], appliedTo: [AppliedTo]) {
        self.id = id
        self.name = name
        self.created = created
        self.rules = rules
        self.appliedTo = appliedTo
    }

    enum CodingKeys: String, CodingKey {
        case id, name, created, rules
        case appliedTo = "applied_to"
    }

    public struct Rule: Sendable, Hashable, Decodable {
        public let direction: String
        public let protocolName: String
        public let port: String?
        public let sourceIps: [String]
        public let destinationIps: [String]
        public let description: String?

        public init(
            direction: String,
            protocolName: String,
            port: String?,
            sourceIps: [String],
            destinationIps: [String],
            description: String? = nil
        ) {
            self.direction = direction
            self.protocolName = protocolName
            self.port = port
            self.sourceIps = sourceIps
            self.destinationIps = destinationIps
            self.description = description
        }

        enum CodingKeys: String, CodingKey {
            case direction, port, description
            case protocolName = "protocol"
            case sourceIps = "source_ips"
            case destinationIps = "destination_ips"
        }
    }

    public struct AppliedTo: Sendable, Hashable, Decodable {
        public let type: String
        public let server: ServerID?
        public let labelSelector: Selector?

        public init(type: String, server: ServerID?, labelSelector: Selector?) {
            self.type = type
            self.server = server
            self.labelSelector = labelSelector
        }

        enum CodingKeys: String, CodingKey {
            case type, server
            case labelSelector = "label_selector"
        }

        public struct ServerID: Sendable, Hashable, Decodable {
            public let id: Int64
        }

        public struct Selector: Sendable, Hashable, Decodable {
            public let selector: String
        }
    }
}

public enum IPType: String, Sendable, Hashable, Codable {
    case ipv4, ipv6
}

public struct PrimaryIP: Sendable, Hashable, Decodable, Identifiable {
    public let id: Int64
    public let name: String
    public let ip: String
    public let type: IPType
    public let created: Date
    public let location: Location
    public let assigneeType: String
    public let assigneeId: Int64?

    public init(
        id: Int64,
        name: String,
        ip: String,
        type: IPType,
        created: Date,
        location: Location,
        assigneeType: String,
        assigneeId: Int64?
    ) {
        self.id = id
        self.name = name
        self.ip = ip
        self.type = type
        self.created = created
        self.location = location
        self.assigneeType = assigneeType
        self.assigneeId = assigneeId
    }

    enum CodingKeys: String, CodingKey {
        case id, name, ip, type, created, location
        case assigneeType = "assignee_type"
        case assigneeId = "assignee_id"
    }

    public var isUnassigned: Bool { assigneeId == nil || assigneeType == "unassigned" }
}

public struct FloatingIP: Sendable, Hashable, Decodable, Identifiable {
    public let id: Int64
    public let name: String
    public let ip: String
    public let type: IPType
    public let created: Date
    public let server: Int64?
    public let homeLocation: Location

    public init(id: Int64, name: String, ip: String, type: IPType, created: Date, server: Int64?, homeLocation: Location) {
        self.id = id
        self.name = name
        self.ip = ip
        self.type = type
        self.created = created
        self.server = server
        self.homeLocation = homeLocation
    }

    enum CodingKeys: String, CodingKey {
        case id, name, ip, type, created, server
        case homeLocation = "home_location"
    }
}

public struct LoadBalancer: Sendable, Hashable, Decodable, Identifiable {
    public let id: Int64
    public let name: String
    public let created: Date
    public let location: Location
    public let loadBalancerType: LoadBalancerType
    public let outgoingTraffic: Int64?
    public let includedTraffic: Int64

    public init(
        id: Int64,
        name: String,
        created: Date,
        location: Location,
        loadBalancerType: LoadBalancerType,
        outgoingTraffic: Int64? = nil,
        includedTraffic: Int64 = 0
    ) {
        self.id = id
        self.name = name
        self.created = created
        self.location = location
        self.loadBalancerType = loadBalancerType
        self.outgoingTraffic = outgoingTraffic
        self.includedTraffic = includedTraffic
    }

    enum CodingKeys: String, CodingKey {
        case id, name, created, location
        case loadBalancerType = "load_balancer_type"
        case outgoingTraffic = "outgoing_traffic"
        case includedTraffic = "included_traffic"
    }

    public struct LoadBalancerType: Sendable, Hashable, Decodable {
        public let id: Int64
        public let name: String
        public let prices: [LocationPrice]

        public init(id: Int64, name: String, prices: [LocationPrice]) {
            self.id = id
            self.name = name
            self.prices = prices
        }
    }
}
