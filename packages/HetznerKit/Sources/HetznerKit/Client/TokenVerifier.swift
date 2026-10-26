import Foundation

public struct WriteProbe: Sendable, Equatable {
    public static let missingID: Int64 = 9_007_199_254_740_991

    public let path: String

    public static let cloud = WriteProbe(path: "/servers/\(missingID)")
    public static let hetzner = WriteProbe(path: "/storage_boxes/\(missingID)")

    static let allowedPaths: Set<String> = [cloud.path, hetzner.path]

    public static func `for`(_ api: HetznerAPI) -> WriteProbe {
        switch api {
        case .cloud: cloud
        case .hetzner: hetzner
        }
    }
}

public enum TokenAccess: String, Sendable, Codable, Equatable {
    case readOnly
    case readWrite

    public var title: String {
        switch self {
        case .readOnly: "Read only"
        case .readWrite: "Read & write"
        }
    }
}

public enum TokenCheck: Sendable, Equatable {
    case readOnly
    case invalid
    case writable
    case unexpected(status: Int, code: String)
    case failed(String)

    public var access: TokenAccess? {
        switch self {
        case .readOnly: .readOnly
        case .writable: .readWrite
        default: nil
        }
    }

    public var isAccepted: Bool { access != nil }

    public var explanation: String {
        switch self {
        case .readOnly:
            "Read-only token."
        case .writable:
            "Read & write token."
        case .invalid:
            "Hetzner did not accept this token. Check that you copied all of it."
        case .unexpected(let status, let code):
            "Could not check this token's permissions (HTTP \(status), \(code)). It was not saved."
        case .failed(let reason):
            "Could not reach Hetzner: \(reason). The token was not saved."
        }
    }
}

public struct TokenVerifier: Sendable {
    public static let readOnlyCodes: Set<String> = ["forbidden", "token_readonly"]

    private let client: HetznerClient

    public init(client: HetznerClient) {
        self.client = client
    }

    public func verify() async -> TokenCheck {
        do {
            switch client.api {
            case .cloud: _ = try await client.servers(maxPages: 1)
            case .hetzner: _ = try await client.storageBoxes(maxPages: 1)
            }
        } catch let error as HetznerError {
            return Self.classifyRead(error)
        } catch {
            return .failed(error.localizedDescription)
        }

        do {
            _ = try await client.probe(.for(client.api))
            return .writable
        } catch let error as HetznerError {
            return Self.classify(error)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func classifyRead(_ error: HetznerError) -> TokenCheck {
        switch error {
        case .api(401, _, _): .invalid
        case .api(let status, let code, _): .unexpected(status: status, code: code)
        case .rateLimited: .failed("rate limit reached, try again in a minute")
        default: .failed(String(describing: error))
        }
    }

    static func classify(_ error: HetznerError) -> TokenCheck {
        switch error {
        case .api(403, let code, _) where readOnlyCodes.contains(code):
            .readOnly
        case .api(401, _, _):
            .invalid
        case .api(404, "not_found", _):
            .writable
        case .api(let status, let code, _):
            .unexpected(status: status, code: code)
        case .rateLimited:
            .failed("rate limit reached, try again in a minute")
        default:
            .failed(String(describing: error))
        }
    }
}
