import Foundation

public enum HetznerError: Error, Sendable, Equatable {
    case api(status: Int, code: String, message: String)
    case rateLimited(resetAt: Date?)
    case hostNotAllowed(String)
    case writeNotAllowed(String)
    case invalidResponse
    case decoding(String)

    public var code: String? {
        if case .api(_, let code, _) = self { return code }
        return nil
    }

    public var status: Int? {
        if case .api(let status, _, _) = self { return status }
        return nil
    }
}

struct APIErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: String
        let message: String
    }

    let error: Body
}
