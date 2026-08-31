import Foundation

public struct AgentRuntimeStatus: Codable, Equatable, Identifiable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case starting
        case ready
        case working
        case retrying
        case unavailable
    }

    public let actorID: String
    public let threadID: String
    public let phase: Phase
    public let detail: String
    public let updatedAt: Date

    public var id: String { actorID }

    public init(
        actorID: String,
        threadID: String,
        phase: Phase,
        detail: String,
        updatedAt: Date = .now
    ) {
        self.actorID = actorID
        self.threadID = threadID
        self.phase = phase
        self.detail = detail
        self.updatedAt = updatedAt
    }

    public static func fileName(actorID: String, threadID: String) -> String {
        "runtime--\(safeComponent(actorID))--\(safeComponent(threadID)).json"
    }

    private static func safeComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let result = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }.joined()
        return result.isEmpty ? "actor" : result
    }
}
