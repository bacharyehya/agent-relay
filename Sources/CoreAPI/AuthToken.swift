import Foundation
import Hummingbird

public struct AuthToken: Equatable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public func matches(request: Request) -> Bool {
        guard let header = request.headers[.authorization] else {
            return false
        }

        let components = header.split(separator: " ", maxSplits: 1).map(String.init)
        guard components.count == 2 else {
            return false
        }
        guard components[0].caseInsensitiveCompare("Bearer") == .orderedSame else {
            return false
        }

        return components[1] == rawValue
    }
}
