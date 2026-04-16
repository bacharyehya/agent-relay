import Foundation

public struct Project: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var summary: String
    public var status: ProjectStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        title: String,
        summary: String = "",
        status: ProjectStatus = .active,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func example(id: String = "project-1") -> Project {
        Project(
            id: id,
            title: "Shield",
            summary: "Operational collaboration workspace"
        )
    }
}

public enum ProjectStatus: String, Codable, Sendable {
    case active
    case paused
    case archived
}
