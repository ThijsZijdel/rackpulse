import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration, delegate: RedirectBlocker(), delegateQueue: nil)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HetznerError.invalidResponse }
        return (data, http)
    }
}

private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

extension URLRequest {
    public var redactedDescription: String {
        var lines = ["\(httpMethod ?? "GET") \(url?.absoluteString ?? "")"]
        for (key, value) in (allHTTPHeaderFields ?? [:]).sorted(by: { $0.key < $1.key }) {
            let shown = key.caseInsensitiveCompare("Authorization") == .orderedSame ? "Bearer <redacted>" : value
            lines.append("\(key): \(shown)")
        }
        return lines.joined(separator: "\n")
    }
}
