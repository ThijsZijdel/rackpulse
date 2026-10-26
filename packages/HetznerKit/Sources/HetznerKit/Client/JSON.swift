import Foundation

enum JSON {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = parseDate(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(text)")
            }
            return date
        }
        return decoder
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder().decode(type, from: data)
        } catch {
            throw HetznerError.decoding(String(describing: error))
        }
    }

    static func decodePage<Item: Decodable>(_ type: Item.Type, key: String, from data: Data) throws -> Page<Item> {
        let decoder = decoder()
        decoder.userInfo[.pageKey] = key
        do {
            return try decoder.decode(Page<Item>.self, from: data)
        } catch {
            throw HetznerError.decoding(String(describing: error))
        }
    }

    static func parseDate(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: .iso8601) { return date }
        return try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    static func format(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .gmt))
    }
}

extension CodingUserInfoKey {
    static let pageKey = CodingUserInfoKey(rawValue: "dev.rackpulse.pageKey")!
}

struct AnyKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

public struct Pagination: Sendable, Equatable, Decodable {
    public let page: Int
    public let perPage: Int
    public let nextPage: Int?
    public let lastPage: Int?
    public let totalEntries: Int?

    enum CodingKeys: String, CodingKey {
        case page
        case perPage = "per_page"
        case nextPage = "next_page"
        case lastPage = "last_page"
        case totalEntries = "total_entries"
    }
}

struct Page<Item: Decodable>: Decodable {
    let items: [Item]
    let pagination: Pagination?

    private struct Meta: Decodable {
        let pagination: Pagination?
    }

    init(from decoder: Decoder) throws {
        guard let key = decoder.userInfo[.pageKey] as? String else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Missing page key"))
        }
        let container = try decoder.container(keyedBy: AnyKey.self)
        items = try container.decode([Item].self, forKey: AnyKey(key))
        pagination = try container.decodeIfPresent(Meta.self, forKey: AnyKey("meta"))?.pagination
    }
}

extension KeyedDecodingContainer {
    func decodeDecimalString(forKey key: Key) throws -> Decimal {
        let text = try decode(String.self, forKey: key)
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Invalid decimal \(text)")
        }
        return value
    }
}
