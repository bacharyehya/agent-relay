import AppCore
import Foundation

struct ListProjectsTool {
    let client: any CoreAPIClientProtocol

    func run() async throws -> String {
        try encode(try await client.listProjects())
    }
}

struct ListThreadsTool {
    let client: any CoreAPIClientProtocol

    func run(projectID: String) async throws -> String {
        try encode(try await client.listThreads(projectID: projectID))
    }
}

struct ListActorsTool {
    let client: any CoreAPIClientProtocol
    let boundActorID: String?

    func run() async throws -> String {
        var actorIDs = Set<String>()
        if let boundActorID, !boundActorID.isEmpty {
            actorIDs.insert(boundActorID)
        }

        for project in try await client.listProjects() {
            for thread in try await client.listThreads(projectID: project.id) {
                actorIDs.insert(thread.createdBy)
                actorIDs.formUnion(thread.assignedActorIDs)
            }
        }

        return try encode(actorIDs.sorted())
    }
}

private func encode<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
