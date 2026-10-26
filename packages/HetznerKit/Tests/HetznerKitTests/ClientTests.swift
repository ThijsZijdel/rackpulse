import Foundation
import Testing
@testable import HetznerKit

struct ClientTests {
    @Test func decodesOfficialSpecExamples() async throws {
        let replies = try [
            "servers", "volumes", "server_actions", "firewalls", "primary_ips",
            "floating_ips", "load_balancers", "pricing", "metrics",
        ].map { StubTransport.Reply(body: try fixture($0)) }
        let client = HetznerClient(api: .cloud, token: "t", transport: StubTransport(replies))

        #expect(try await client.servers().first?.serverType.name == "cpx22")
        #expect(try await client.volumes().count == 1)
        #expect(try await client.recentServerActions().count == 1)
        #expect(try await client.firewalls().count == 1)
        #expect(try await client.primaryIPs().count == 1)
        #expect(try await client.floatingIPs().count == 1)
        #expect(try await client.loadBalancers().count == 1)
        #expect(try await client.pricing().serverBackupPercentage == 20)

        let metrics = try await client.metrics(server: 1, start: .now.addingTimeInterval(-3600), end: .now)
        #expect(metrics.points(MetricSeries.networkBandwidthOut).count == 11)
        #expect(metrics.cpuPercent(cores: 4).last?.value == 88.75)

        let boxes = try await HetznerClient(
            api: .hetzner, token: "t", transport: StubTransport([.init(body: try fixture("storage_boxes"))])
        ).storageBoxes()
        #expect(abs((boxes.first?.usedFraction ?? 0) - 0.8) < 0.001)
    }

    @Test func followsPaginationAndTracksRateLimit() async throws {
        let page = try JSONSerialization.jsonObject(with: try fixture("servers")) as! [String: Any]
        func body(next: Int?) throws -> Data {
            var copy = page
            copy["meta"] = ["pagination": ["page": 1, "per_page": 50, "next_page": next as Any? ?? NSNull()]]
            return try JSONSerialization.data(withJSONObject: copy)
        }
        let reset = Date.now.addingTimeInterval(600)
        let headers = ["RateLimit-Limit": "3600", "RateLimit-Remaining": "0",
                       "RateLimit-Reset": String(Int(reset.timeIntervalSince1970))]
        let transport = StubTransport([.init(body: try body(next: 2)), .init(body: try body(next: nil), headers: headers)])
        let client = HetznerClient(api: .cloud, token: "secret", transport: transport)

        #expect(try await client.servers().count == 2)
        let queries = transport.requests.map { $0.url!.query()! }
        #expect(queries == ["page=1&per_page=50", "page=2&per_page=50"])
        #expect(!transport.requests[0].redactedDescription.contains("secret"))

        await #expect(throws: HetznerError.rateLimited(resetAt: Date(timeIntervalSince1970: reset.timeIntervalSince1970.rounded(.down)))) {
            try await client.volumes()
        }
        #expect(transport.requests.count == 2)
    }

    @Test(arguments: [
        (403, "forbidden", TokenCheck.readOnly),
        (403, "token_readonly", .readOnly),
        (404, "not_found", .writable),
        (422, "invalid_input", .unexpected(status: 422, code: "invalid_input")),
    ])
    func tokenCheckClassifiesAccess(status: Int, code: String, expected: TokenCheck) async throws {
        let transport = StubTransport([
            .init(body: try fixture("servers")),
            .init(status: status, body: errorBody(code)),
        ])
        let check = await TokenVerifier(client: HetznerClient(api: .cloud, token: "t", transport: transport)).verify()
        #expect(check == expected)
        let probe = transport.requests[1]
        #expect(probe.httpMethod == "PUT")
        #expect(probe.url!.path() == "/v1/servers/\(WriteProbe.missingID)")
        #expect(probe.httpBody == Data("{}".utf8))
    }

    @Test func onlyReadWriteClientsSendPowerActions() async throws {
        let readOnly = HetznerClient(api: .cloud, token: "t", transport: StubTransport([]))
        await #expect(throws: HetznerError.writeNotAllowed("/servers/7/actions/poweroff")) {
            try await readOnly.power(.powerOff, server: 7)
        }

        let transport = StubTransport([.init(status: 201, body: Data("{}".utf8))])
        let readWrite = HetznerClient(api: .cloud, token: "t", access: .readWrite, transport: transport)
        try await readWrite.power(.shutdown, server: 7)
        #expect(transport.requests.map { "\($0.httpMethod!) \($0.url!.path())" } == ["POST /v1/servers/7/actions/shutdown"])
        #expect(PowerAction.allows("/servers/7") == false)
        #expect(PowerAction.allows("/servers/7/actions/rebuild") == false)
    }

    @Test(arguments: [
        (401, "unauthorized", TokenCheck.invalid),
        (403, "forbidden", .unexpected(status: 403, code: "forbidden")),
    ])
    func failedReadNeverReachesTheProbe(status: Int, code: String, expected: TokenCheck) async throws {
        let transport = StubTransport([.init(status: status, body: errorBody(code))])
        let check = await TokenVerifier(client: HetznerClient(api: .cloud, token: "t", transport: transport)).verify()
        #expect(check == expected)
        #expect(transport.requests.count == 1)
    }
}
