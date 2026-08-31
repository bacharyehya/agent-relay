import Foundation

/// A small, lossless JSON value used at the app-server protocol boundary.
///
/// Keeping this type independent from `[String: Any]` makes the transport
/// deterministic and Sendable under Swift 6 strict concurrency.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    public var arrayValue: [JSONValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    public var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    public var integerValue: Int64? {
        switch self {
        case let .integer(value):
            value
        case let .double(value) where value.rounded() == value:
            Int64(exactly: value)
        default:
            nil
        }
    }

    public var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }
}

public enum JSONRPCID: Hashable, Sendable {
    case integer(Int64)
    case string(String)

    init?(jsonValue: JSONValue?) {
        switch jsonValue {
        case let .integer(value):
            self = .integer(value)
        case let .string(value):
            self = .string(value)
        default:
            return nil
        }
    }

    var jsonValue: JSONValue {
        switch self {
        case let .integer(value):
            .integer(value)
        case let .string(value):
            .string(value)
        }
    }
}
