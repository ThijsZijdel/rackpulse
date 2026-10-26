import Foundation

public enum HetznerAPI: String, Sendable, Codable, CaseIterable {
    case cloud
    case hetzner

    public static let allowedHosts: Set<String> = ["api.hetzner.cloud", "api.hetzner.com"]

    public var baseURL: URL {
        switch self {
        case .cloud: URL(string: "https://api.hetzner.cloud/v1")!
        case .hetzner: URL(string: "https://api.hetzner.com/v1")!
        }
    }

    public var host: String { baseURL.host()! }
}
