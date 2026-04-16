import Foundation

struct ListRecentsTool {
    let client: any CoreAPIClientProtocol

    func run() async throws -> String {
        let items = try await client.listRecents()
        guard !items.isEmpty else {
            return "No recent events."
        }

        return items
            .map { "\($0.type.rawValue): \($0.body)" }
            .joined(separator: "\n")
    }
}

struct CreateHandoffTool {
    let client: any CoreAPIClientProtocol

    func run(request: CreateHandoffPayload) async throws -> String {
        let handoff = try await client.createHandoff(request)
        return "Created handoff \(handoff.id): \(handoff.title)"
    }
}

struct RespondHandoffTool {
    let client: any CoreAPIClientProtocol

    func run(id: String, body: String) async throws -> String {
        let handoff = try await client.updateHandoff(id: id, status: .responded, resolution: body)
        return "Responded to \(handoff.id): \(handoff.title)"
    }
}
