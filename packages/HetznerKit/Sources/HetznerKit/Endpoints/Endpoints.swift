import Foundation

extension HetznerClient {
    public func servers(maxPages: Int = .max) async throws -> [Server] {
        try await list("/servers", key: "servers", maxPages: maxPages)
    }

    public func metrics(
        server id: Int64,
        types: [MetricType] = MetricType.allCases,
        start: Date,
        end: Date,
        step: Int? = nil
    ) async throws -> ServerMetrics {
        var query = [
            URLQueryItem(name: "type", value: types.map(\.rawValue).joined(separator: ",")),
            URLQueryItem(name: "start", value: JSON.format(start)),
            URLQueryItem(name: "end", value: JSON.format(end)),
        ]
        if let step { query.append(URLQueryItem(name: "step", value: String(step))) }
        let data: MetricsEnvelope = try await get("/servers/\(id)/metrics", query: query)
        return data.metrics
    }

    public func volumes() async throws -> [Volume] {
        try await list("/volumes", key: "volumes")
    }

    public func recentServerActions(maxPages: Int = 1) async throws -> [ServerAction] {
        try await list(
            "/servers/actions",
            key: "actions",
            query: [URLQueryItem(name: "sort", value: "started:desc")],
            maxPages: maxPages
        )
    }

    public func actions(server id: Int64, limit: Int = 10) async throws -> [ServerAction] {
        try await list(
            "/servers/\(id)/actions",
            key: "actions",
            query: [URLQueryItem(name: "sort", value: "started:desc")],
            maxPages: 1
        ).prefix(limit).map { $0 }
    }

    public func recentVolumeActions() async throws -> [ServerAction] {
        try await list(
            "/volumes/actions",
            key: "actions",
            query: [URLQueryItem(name: "sort", value: "started:desc")],
            maxPages: 1
        )
    }

    public func firewalls() async throws -> [Firewall] {
        try await list("/firewalls", key: "firewalls")
    }

    public func primaryIPs() async throws -> [PrimaryIP] {
        try await list("/primary_ips", key: "primary_ips")
    }

    public func floatingIPs() async throws -> [FloatingIP] {
        try await list("/floating_ips", key: "floating_ips")
    }

    public func loadBalancers() async throws -> [LoadBalancer] {
        try await list("/load_balancers", key: "load_balancers")
    }

    public func serverTypes() async throws -> [ServerType] {
        try await list("/server_types", key: "server_types")
    }

    public func pricing() async throws -> Pricing {
        let data: PricingEnvelope = try await get("/pricing")
        return data.pricing
    }

    public func storageBoxes(maxPages: Int = .max) async throws -> [StorageBox] {
        try await list("/storage_boxes", key: "storage_boxes", maxPages: maxPages)
    }
}

private struct MetricsEnvelope: Decodable {
    let metrics: ServerMetrics
}

private struct PricingEnvelope: Decodable {
    let pricing: Pricing
}
