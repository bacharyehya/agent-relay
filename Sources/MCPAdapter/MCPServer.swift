import AppCore
import Foundation

final class MCPServer {
    private let listInboxTool: ListInboxTool
    private let listRecentsTool: ListRecentsTool
    private let getThreadTool: GetThreadTool
    private let createHandoffTool: CreateHandoffTool
    private let respondHandoffTool: RespondHandoffTool

    init(client: any CoreAPIClientProtocol) {
        self.listInboxTool = ListInboxTool(client: client)
        self.listRecentsTool = ListRecentsTool(client: client)
        self.getThreadTool = GetThreadTool(client: client)
        self.createHandoffTool = CreateHandoffTool(client: client)
        self.respondHandoffTool = RespondHandoffTool(client: client)
    }

    func run() async throws {
        while let line = readLine() {
            guard !line.isEmpty else { continue }

            let response: String
            do {
                response = try await handle(line: line)
            } catch {
                response = rpcResponse(
                    id: nil,
                    error: [
                        "code": -32000,
                        "message": String(describing: error),
                    ]
                )
            }

            FileHandle.standardOutput.write(Data(response.utf8))
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    private func handle(line: String) async throws -> String {
        guard
            let data = line.data(using: .utf8),
            let request = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return rpcResponse(
                id: nil,
                error: [
                    "code": -32700,
                    "message": "Invalid JSON",
                ]
            )
        }

        let id = request["id"]
        let method = request["method"] as? String ?? ""

        switch method {
        case "tools/list":
            return rpcResponse(
                id: id,
                result: [
                    "tools": [
                        toolDescription(name: "list_inbox", description: "List open inbox handoffs for an actor"),
                        toolDescription(name: "list_recents", description: "List recent collaboration events"),
                        toolDescription(name: "get_thread", description: "Fetch bounded thread context"),
                        toolDescription(name: "create_handoff", description: "Create a new handoff"),
                        toolDescription(name: "respond_handoff", description: "Respond to a handoff with a resolution"),
                    ],
                ]
            )
        case "tools/call":
            guard
                let params = request["params"] as? [String: Any],
                let name = params["name"] as? String
            else {
                return rpcResponse(
                    id: id,
                    error: [
                        "code": -32602,
                        "message": "Invalid tool call parameters",
                    ]
                )
            }

            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let text = try await callTool(named: name, arguments: arguments)
            return rpcResponse(
                id: id,
                result: [
                    "content": [
                        [
                            "type": "text",
                            "text": text,
                        ],
                    ],
                ]
            )
        default:
            return rpcResponse(
                id: id,
                error: [
                    "code": -32601,
                    "message": "Method not found",
                ]
            )
        }
    }

    private func callTool(named name: String, arguments: [String: Any]) async throws -> String {
        switch name {
        case "list_inbox":
            guard let actorID = arguments["actor_id"] as? String else {
                throw NSError(domain: "MCPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "actor_id is required"])
            }
            return try await listInboxTool.run(actorID: actorID)
        case "list_recents":
            return try await listRecentsTool.run()
        case "get_thread":
            guard let threadID = arguments["thread_id"] as? String else {
                throw NSError(domain: "MCPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "thread_id is required"])
            }
            let mode = arguments["mode"] as? String ?? "recent"
            return try await getThreadTool.run(threadID: threadID, mode: mode)
        case "create_handoff":
            guard
                let threadID = arguments["thread_id"] as? String,
                let title = arguments["title"] as? String,
                let summary = arguments["summary"] as? String,
                let ask = arguments["ask"] as? String,
                let priorityRawValue = arguments["priority"] as? String,
                let priority = HandoffPriority(rawValue: priorityRawValue),
                let createdBy = arguments["created_by"] as? String,
                let assignedTo = arguments["assigned_to"] as? String
            else {
                throw NSError(domain: "MCPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing required create_handoff arguments"])
            }
            let sourceRefs = arguments["source_refs"] as? [String] ?? []
            return try await createHandoffTool.run(
                request: CreateHandoffPayload(
                    threadID: threadID,
                    title: title,
                    summary: summary,
                    ask: ask,
                    priority: priority,
                    createdBy: createdBy,
                    assignedTo: assignedTo,
                    sourceRefs: sourceRefs
                )
            )
        case "respond_handoff":
            guard
                let id = arguments["id"] as? String,
                let body = arguments["body"] as? String
            else {
                throw NSError(domain: "MCPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "id and body are required"])
            }
            return try await respondHandoffTool.run(id: id, body: body)
        default:
            throw NSError(domain: "MCPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown tool \(name)"])
        }
    }

    private func toolDescription(name: String, description: String) -> [String: Any] {
        [
            "name": name,
            "description": description,
        ]
    }

    private func rpcResponse(
        id: Any?,
        result: [String: Any]? = nil,
        error: [String: Any]? = nil
    ) -> String {
        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
        ]
        if let result {
            payload["result"] = result
        }
        if let error {
            payload["error"] = error
        }

        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
