import Foundation
import Testing
@testable import HetznerKit

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

final class StubTransport: HTTPTransport, @unchecked Sendable {
    struct Reply {
        var status = 200
        var body: Data
        var headers: [String: String] = [:]
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply = lock.withLock {
            requests.append(request)
            return replies.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
        return (reply.body, response)
    }
}

func errorBody(_ code: String) -> Data {
    Data(#"{"error":{"code":"\#(code)","message":"x"}}"#.utf8)
}

let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}()

func date(_ text: String) -> Date {
    try! Date(text, strategy: .iso8601)
}

func money(_ text: String) -> Price {
    let value = Decimal(string: text)!
    return Price(net: value, gross: value)
}

func price(_ hourly: String?, _ monthly: String, at location: String = "fsn1") -> LocationPrice {
    LocationPrice(location: location, priceHourly: hourly.map(money), priceMonthly: money(monthly))
}

func server(
    _ id: Int64,
    status: ServerStatus = .running,
    cores: Double = 2,
    created: Date = date("2026-01-01T00:00:00Z"),
    hourly: String = "0.01",
    monthly: String = "5",
    backups: Bool = false
) -> Server {
    Server(
        id: id,
        name: "server-\(id)",
        status: status,
        created: created,
        serverType: ServerType(id: 1, name: "cx22", description: "CX22", cores: cores, memory: 4, disk: 40,
                               prices: [price(hourly, monthly)]),
        location: Location(id: 1, name: "fsn1"),
        backupWindow: backups ? "22-02" : nil
    )
}
