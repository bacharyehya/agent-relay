import AppCore
import Foundation

final class MCPServer {
    private static let currentProtocolVersion = "2025-06-18"
    private static let supportedProtocolVersions = ["2025-06-18", "2024-11-05"]

    private let listProjectsTool: ListProjectsTool
    private let listThreadsTool: ListThreadsTool
    private let listActorsTool: ListActorsTool
    private let listInboxTool: ListInboxTool
    private let listRecentsTool: ListRecentsTool
    private let getThreadTool: GetThreadTool
    private let getMessagesTool: GetMessagesTool
    private let postMessageTool: PostMessageTool
    private let createHandoffTool: CreateHandoffTool
    private let respondHandoffTool: RespondHandoffTool
    private let actorID: String?

    init(client: any CoreAPIClientProtocol, actorID: String? = nil) {
        self.listProjectsTool = ListProjectsTool(client: client)
        self.listThreadsTool = ListThreadsTool(client: client)
        self.listActorsTool = ListActorsTool(client: client, boundActorID: actorID)
        self.listInboxTool = ListInboxTool(client: client)
        self.listRecentsTool = ListRecentsTool(client: client)
        self.getThreadTool = GetThreadTool(client: client)
        self.getMessagesTool = GetMessagesTool(client: client)
        self.postMessageTool = PostMessageTool(client: client, actorID: actorID)
        self.createHandoffTool = CreateHandoffTool(client: client)
        self.respondHandoffTool = RespondHandoffTool(client: client)
        self.actorID = actorID
    }

    func run() async throws {
        while let line = readLine() {
            guard !line.isEmpty else { continue }

            let response: String?
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

            guard let response else { continue }
            FileHandle.standardOutput.write(Data(response.utf8))
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    func handle(line: String) async throws -> String? {
        guard let data = line.data(using: .utf8) else {
            return rpcResponse(
                id: nil,
                error: [
                    "code": -32700,
                    "message": "Invalid JSON",
                ]
            )
        }
        let request: [String: Any]
        do {
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "MCPServer", code: 0)
            }
            request = decoded
        } catch {
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
        case "initialize":
            let params = request["params"] as? [String: Any]
            let requestedVersion = params?["protocolVersion"] as? String
            let protocolVersion = requestedVersion.flatMap { requested in
                Self.supportedProtocolVersions.contains(requested) ? requested : nil
            } ?? Self.currentProtocolVersion
            let identityInstruction = actorID.map {
                "post_message is bound to the authenticated local actor identity '\($0)'."
            } ?? "Set AGENT_RELAY_ACTOR_ID to enable post_message with a bound sender identity."

            return rpcResponse(
                id: id,
                result: [
                    "protocolVersion": protocolVersion,
                    "capabilities": [
                        "tools": ["listChanged": false],
                    ],
                    "serverInfo": [
                        "name": "agent-relay",
                        "version": "0.2.0",
                    ],
                    "instructions": "Use Agent Relay for visible, durable agent collaboration. \(identityInstruction)",
                ]
            )
        case "notifications/initialized", "notifications/cancelled":
            return nil
        case let notification where notification.hasPrefix("notifications/"):
            return nil
        case "ping":
            return rpcResponse(id: id, result: [:])
        case "tools/list":
            return rpcResponse(id: id, result: ["tools": toolDescriptions()])
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
            do {
                let text = try await callTool(named: name, arguments: arguments)
                return toolResponse(id: id, text: text, isError: false)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                return toolResponse(id: id, text: message, isError: true)
            }
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
        case "list_projects":
            return try await listProjectsTool.run()
        case "list_threads", "list_rooms":
            guard let projectID = arguments["project_id"] as? String else {
                throw toolError("project_id is required")
            }
            return try await listThreadsTool.run(projectID: projectID)
        case "list_actors":
            return try await listActorsTool.run()
        case "list_inbox":
            guard let actorID = arguments["actor_id"] as? String else {
                throw NSError(domain: "MCPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "actor_id is required"])
            }
            return try await listInboxTool.run(actorID: actorID)
        case "list_recents":
            return try await listRecentsTool.run()
        case "get_thread":
            guard let threadID = arguments["thread_id"] as? String else {
                throw toolError("thread_id is required")
            }
            let mode = arguments["mode"] as? String ?? "recent"
            return try await getThreadTool.run(threadID: threadID, mode: mode)
        case "get_messages":
            guard let threadID = arguments["thread_id"] as? String else {
                throw toolError("thread_id is required")
            }
            let limit = arguments["limit"] as? Int ?? 100
            guard (1...200).contains(limit) else {
                throw toolError("limit must be between 1 and 200")
            }
            let before = try parseMessageCursor(arguments["before_cursor"])
            return try await getMessagesTool.run(threadID: threadID, limit: limit, before: before)
        case "post_message":
            guard
                let threadID = arguments["thread_id"] as? String,
                let body = arguments["body"] as? String,
                let idempotencyKey = arguments["idempotency_key"] as? String,
                !idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw toolError("thread_id, body, and idempotency_key are required")
            }
            let format: MessageFormat
            if let rawFormat = arguments["format"] as? String {
                guard let parsedFormat = MessageFormat(rawValue: rawFormat) else {
                    throw toolError("format must be markdown or plainText")
                }
                format = parsedFormat
            } else {
                format = .markdown
            }
            return try await postMessageTool.run(
                threadID: threadID,
                body: body,
                format: format,
                replyToMessageID: arguments["reply_to_message_id"] as? String,
                mentionedActorIDs: arguments["mentioned_actor_ids"] as? [String] ?? [],
                idempotencyKey: idempotencyKey,
                requestedActorID: arguments["actor_id"] as? String
            )
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
            throw toolError("Unknown tool \(name)")
        }
    }

    private func toolDescriptions() -> [[String: Any]] {
        let descriptions = [
            toolDescription(
                name: "list_projects",
                description: "List visible Agent Relay projects.",
                properties: [:]
            ),
            toolDescription(
                name: "list_threads",
                description: "List the rooms/threads in a project.",
                properties: ["project_id": stringSchema("Project identifier")],
                required: ["project_id"]
            ),
            toolDescription(
                name: "list_rooms",
                description: "Alias for list_threads; list collaboration rooms in a project.",
                properties: ["project_id": stringSchema("Project identifier")],
                required: ["project_id"]
            ),
            toolDescription(
                name: "list_actors",
                description: "List actor identifiers known from thread creators and assignments.",
                properties: [:]
            ),
            toolDescription(
                name: "list_inbox",
                description: "List open inbox handoffs for an actor.",
                properties: ["actor_id": stringSchema("Actor identifier")],
                required: ["actor_id"]
            ),
            toolDescription(
                name: "list_recents",
                description: "List recent collaboration events.",
                properties: [:]
            ),
            toolDescription(
                name: "get_thread",
                description: "Fetch bounded thread context including messages and handoffs.",
                properties: [
                    "thread_id": stringSchema("Thread identifier"),
                    "mode": [
                        "type": "string",
                        "enum": ["recent", "recentAndReferenced", "handoffFocused"],
                        "description": "Context selection mode",
                    ],
                ],
                required: ["thread_id"]
            ),
            toolDescription(
                name: "get_messages",
                description: "Read a chronological page of visible messages from a thread.",
                properties: [
                    "thread_id": stringSchema("Thread identifier"),
                    "limit": [
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 200,
                        "description": "Maximum number of messages to return",
                    ],
                    "before_cursor": [
                        "type": "object",
                        "properties": [
                            "created_at": [
                                "type": "string",
                                "format": "date-time",
                                "description": "Timestamp from the prior page's nextCursor",
                            ],
                            "message_id": stringSchema("Message ID from the prior page's nextCursor"),
                        ],
                        "required": ["created_at", "message_id"],
                        "additionalProperties": false,
                        "description": "Stable composite cursor returned by a prior get_messages call",
                    ],
                ],
                required: ["thread_id"]
            ),
            toolDescription(
                name: "post_message",
                description: "Post a visible message using the server's AGENT_RELAY_ACTOR_ID identity.",
                properties: [
                    "thread_id": stringSchema("Thread identifier"),
                    "body": stringSchema("Message body"),
                    "format": [
                        "type": "string",
                        "enum": ["markdown", "plainText"],
                        "description": "Message body format",
                    ],
                    "reply_to_message_id": stringSchema("Optional message being replied to"),
                    "idempotency_key": stringSchema(
                        "Stable client-generated key; reuse it when retrying the same logical message"
                    ),
                    "mentioned_actor_ids": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Actors explicitly mentioned by this message",
                    ],
                ],
                required: ["thread_id", "body", "idempotency_key"]
            ),
            toolDescription(
                name: "create_handoff",
                description: "Create a new handoff.",
                properties: [
                    "thread_id": stringSchema("Thread identifier"),
                    "title": stringSchema("Short handoff title"),
                    "summary": stringSchema("Current context summary"),
                    "ask": stringSchema("Concrete request for the recipient"),
                    "priority": [
                        "type": "string",
                        "enum": ["low", "medium", "high", "urgent"],
                        "description": "Handoff priority",
                    ],
                    "created_by": stringSchema("Creating actor identifier"),
                    "assigned_to": stringSchema("Recipient actor identifier"),
                    "source_refs": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Related message or source identifiers",
                    ],
                ],
                required: ["thread_id", "title", "summary", "ask", "priority", "created_by", "assigned_to"]
            ),
            toolDescription(
                name: "respond_handoff",
                description: "Respond to a handoff with a resolution.",
                properties: [
                    "id": stringSchema("Handoff identifier"),
                    "body": stringSchema("Resolution body"),
                ],
                required: ["id", "body"]
            ),
        ]
        if actorID == nil {
            return descriptions.filter { $0["name"] as? String != "post_message" }
        }
        return descriptions
    }

    private func toolDescription(
        name: String,
        description: String,
        properties: [String: Any],
        required: [String] = []
    ) -> [String: Any] {
        var inputSchema: [String: Any] = [
            "type": "object",
            "properties": properties,
            "additionalProperties": false,
        ]
        if !required.isEmpty {
            inputSchema["required"] = required
        }
        return [
            "name": name,
            "description": description,
            "inputSchema": inputSchema,
        ]
    }

    private func stringSchema(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private func parseISO8601(_ rawValue: String?) throws -> Date? {
        guard let rawValue else { return nil }
        guard let date = PreciseDateCodec.date(from: rawValue) else {
            throw toolError("before must be an ISO-8601 timestamp")
        }
        return date
    }

    private func parseMessageCursor(_ rawValue: Any?) throws -> MessageCursor? {
        guard let rawValue else { return nil }
        guard
            let object = rawValue as? [String: Any],
            let createdAtValue = object["created_at"] as? String,
            let messageID = object["message_id"] as? String,
            !messageID.isEmpty,
            let createdAt = try parseISO8601(createdAtValue)
        else {
            throw toolError("before_cursor requires created_at and message_id")
        }
        return MessageCursor(createdAt: createdAt, messageID: messageID)
    }

    private func toolResponse(id: Any?, text: String, isError: Bool) -> String {
        rpcResponse(
            id: id,
            result: [
                "content": [["type": "text", "text": text]],
                "isError": isError,
            ]
        )
    }

    private func toolError(_ message: String) -> NSError {
        NSError(
            domain: "MCPServer",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
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
