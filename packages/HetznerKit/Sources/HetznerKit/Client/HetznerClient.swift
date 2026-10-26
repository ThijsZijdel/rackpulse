import Foundation

public actor HetznerClient {
    public nonisolated let api: HetznerAPI
    public nonisolated let access: TokenAccess
    private let token: String
    private let transport: HTTPTransport
    private let clock: @Sendable () -> Date
    public private(set) var rateLimit: RateLimit?

    public static let maxPerPage = 50

    public init(
        api: HetznerAPI,
        token: String,
        access: TokenAccess = .readOnly,
        transport: HTTPTransport = URLSessionTransport(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.api = api
        self.access = access
        self.token = token
        self.transport = transport
        self.clock = clock
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await send(method: "GET", path: path, query: query, body: nil)
        return try JSON.decode(T.self, from: data)
    }

    func list<Item: Decodable>(
        _ path: String,
        key: String,
        query: [URLQueryItem] = [],
        maxPages: Int = .max
    ) async throws -> [Item] {
        var items: [Item] = []
        var page = 1
        var fetched = 0
        while true {
            let paging = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(Self.maxPerPage)),
            ]
            let data = try await send(method: "GET", path: path, query: query + paging, body: nil)
            let result = try JSON.decodePage(Item.self, key: key, from: data)
            items += result.items
            fetched += 1
            guard let next = result.pagination?.nextPage, next > page, fetched < maxPages else { break }
            page = next
        }
        return items
    }

    public func actions(server id: Int64, since: Date, maxPages: Int = 10) async throws -> (actions: [ServerAction], complete: Bool) {
        var items: [ServerAction] = []
        var page = 1
        while true {
            let query = [
                URLQueryItem(name: "sort", value: "started:desc"),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(Self.maxPerPage)),
            ]
            let data = try await send(method: "GET", path: "/servers/\(id)/actions", query: query, body: nil)
            let result = try JSON.decodePage(ServerAction.self, key: "actions", from: data)
            items += result.items
            if result.items.contains(where: { $0.started < since }) { return (items, true) }
            guard let next = result.pagination?.nextPage, next > page else { return (items, true) }
            guard page < maxPages else { return (items, false) }
            page = next
        }
    }

    public func power(_ action: PowerAction, server id: Int64) async throws {
        _ = try await send(method: "POST", path: action.path(server: id), query: [], body: nil)
    }

    func probe(_ probe: WriteProbe) async throws -> Data {
        try await send(method: "PUT", path: probe.path, query: [], body: Data("{}".utf8))
    }

    private func send(method: String, path: String, query: [URLQueryItem], body: Data?) async throws -> Data {
        if method != "GET" {
            let probe = method == "PUT" && WriteProbe.allowedPaths.contains(path)
            let power = method == "POST" && access == .readWrite && api == .cloud && PowerAction.allows(path)
            guard probe || power else { throw HetznerError.writeNotAllowed(path) }
        }
        if let rateLimit, rateLimit.isExhausted(at: clock()) {
            throw HetznerError.rateLimited(resetAt: rateLimit.resetAt)
        }
        let request = try makeRequest(method: method, path: path, query: query, body: body)
        let (data, response) = try await transport.send(request)
        if let limit = RateLimit(headers: response) { rateLimit = limit }
        if (200..<300).contains(response.statusCode) { return data }
        if response.statusCode == 429 {
            throw HetznerError.rateLimited(resetAt: rateLimit?.resetAt)
        }
        let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
        throw HetznerError.api(
            status: response.statusCode,
            code: envelope?.error.code ?? "http_\(response.statusCode)",
            message: envelope?.error.message ?? ""
        )
    }

    private func makeRequest(method: String, path: String, query: [URLQueryItem], body: Data?) throws -> URLRequest {
        guard var components = URLComponents(url: api.baseURL, resolvingAgainstBaseURL: false) else {
            throw HetznerError.hostNotAllowed(path)
        }
        components.path += path
        if !query.isEmpty {
            components.queryItems = query
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        guard
            let url = components.url,
            url.scheme == "https",
            let host = url.host(),
            HetznerAPI.allowedHosts.contains(host)
        else { throw HetznerError.hostNotAllowed(components.host ?? path) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Rackpulse", forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}
