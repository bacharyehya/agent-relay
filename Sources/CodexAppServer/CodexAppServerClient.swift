import Foundation

public actor CodexAppServerClient {
    private enum ConnectionState {
        case idle
        case starting
        case ready(CodexAppServerInfo)
        case terminating
        case closed
    }

    private typealias ResponseContinuation = AsyncThrowingStream<JSONValue, any Error>.Continuation
    private typealias TurnContinuation = AsyncThrowingStream<CodexTurnEvent, any Error>.Continuation

    private let transport: any CodexAppServerTransport
    private let clientName: String
    private let clientTitle: String
    private let clientVersion: String
    private let requestTimeout: Duration

    private var state: ConnectionState = .idle
    private var nextRequestID: Int64 = 1
    private var readerTask: Task<Void, Never>?
    private var pendingResponses: [JSONRPCID: ResponseContinuation] = [:]
    private var eventContinuations: [UUID: AsyncStream<CodexAppServerEvent>.Continuation] = [:]
    private var outstandingInteractions: [JSONRPCID: CodexInteractionRequest] = [:]

    private var cachedAccountSummary: AccountSummary?
    private var activeTurns: [String: CodexTurnHandle] = [:]
    private var turnContinuations: [String: TurnContinuation] = [:]
    private var bufferedTurnEvents: [String: [CodexTurnEvent]] = [:]
    private var completedAgentMessages: [String: [CodexAgentMessage]] = [:]
    private var completedTurns: [String: CodexTurnResult] = [:]

    public init(
        transport: any CodexAppServerTransport = CodexProcessTransport(),
        clientName: String = "agent_relay",
        clientTitle: String = "Agent Relay",
        clientVersion: String = "0.1.0",
        requestTimeout: Duration = .seconds(20)
    ) {
        self.transport = transport
        self.clientName = clientName
        self.clientTitle = clientTitle
        self.clientVersion = clientVersion
        self.requestTimeout = requestTimeout
    }

    @discardableResult
    public func connect() async throws -> CodexAppServerInfo {
        switch state {
        case let .ready(info):
            return info
        case .idle:
            break
        case .starting:
            throw CodexAppServerError.invalidState("Codex app-server is already connecting.")
        case .terminating:
            throw CodexAppServerError.invalidState("Codex app-server is terminating.")
        case .closed:
            throw CodexAppServerError.invalidState("This Codex app-server client has been closed.")
        }

        state = .starting

        do {
            try await transport.start()
            let messages = await transport.messages()
            readerTask = Task { [weak self] in
                do {
                    for try await message in messages {
                        guard let self else { return }
                        await self.receive(message)
                    }
                    guard let self else { return }
                    await self.readerEnded(error: nil)
                } catch {
                    guard let self else { return }
                    await self.readerEnded(error: error)
                }
            }

            let result = try await request(
                method: "initialize",
                parameters: .object([
                    "clientInfo": .object([
                        "name": .string(clientName),
                        "title": .string(clientTitle),
                        "version": .string(clientVersion),
                    ]),
                    "capabilities": .object([
                        "experimentalApi": .bool(true),
                    ]),
                ])
            )
            let info = try parseInitializeResponse(result)

            try await sendNotification(method: "initialized", parameters: .object([:]))
            state = .ready(info)
            return info
        } catch {
            state = .closed
            await transport.terminate()
            throw error
        }
    }

    /// Reads only the account type and ChatGPT plan. Email addresses, tokens,
    /// and other account material are deliberately not represented by the
    /// public model.
    public func accountSummary() async throws -> AccountSummary {
        _ = try await connect()
        let result = try await request(
            method: "account/read",
            parameters: .object(["refreshToken": .bool(false)])
        )
        let summary = try parseAccountSummary(result)
        cachedAccountSummary = summary
        return summary
    }

    /// Returns configured MCP server identifiers without decoding, retaining,
    /// or exposing any server configuration values or credentials.
    public func configuredMCPServerNames(cwd: URL? = nil) async throws -> [String] {
        _ = try await connect()
        var parameters: [String: JSONValue] = ["includeLayers": .bool(false)]
        if let cwd {
            parameters["cwd"] = .string(cwd.path(percentEncoded: false))
        }
        let result = try await request(method: "config/read", parameters: .object(parameters))
        guard let config = result["config"]?.objectValue else {
            throw CodexAppServerError.invalidResponse(
                method: "config/read",
                reason: "missing config object"
            )
        }
        guard let rawServers = config["mcp_servers"] else {
            return []
        }
        guard let servers = rawServers.objectValue else {
            throw CodexAppServerError.invalidResponse(
                method: "config/read",
                reason: "mcp_servers was not an object"
            )
        }
        return servers.keys.sorted()
    }

    public func startThread(
        cwd: URL? = nil,
        model: String? = nil
    ) async throws -> CodexThreadSession {
        try await startThread(
            configuration: CodexThreadConfiguration(
                workingDirectory: cwd,
                model: model
            )
        )
    }

    public func startThread(
        configuration: CodexThreadConfiguration
    ) async throws -> CodexThreadSession {
        try await requireChatGPTManagedAccount()

        let parameters = threadParameters(configuration)

        let result = try await request(method: "thread/start", parameters: .object(parameters))
        return try parseThreadResponse(result, method: "thread/start")
    }

    public func resumeThread(
        id: String,
        cwd: URL? = nil,
        model: String? = nil
    ) async throws -> CodexThreadSession {
        try await resumeThread(
            id: id,
            configuration: CodexThreadConfiguration(
                workingDirectory: cwd,
                model: model
            )
        )
    }

    public func resumeThread(
        id: String,
        configuration: CodexThreadConfiguration
    ) async throws -> CodexThreadSession {
        try await requireChatGPTManagedAccount()

        var parameters = threadParameters(configuration)
        parameters["threadId"] = .string(id)

        let result = try await request(method: "thread/resume", parameters: .object(parameters))
        return try parseThreadResponse(result, method: "thread/resume")
    }

    public func startTurn(threadID: String, input: String) async throws -> CodexTurnHandle {
        try await requireChatGPTManagedAccount()
        let result = try await request(
            method: "turn/start",
            parameters: .object([
                "threadId": .string(threadID),
                "input": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string(input),
                    ]),
                ]),
            ])
        )

        guard let turnID = result["turn"]?["id"]?.stringValue else {
            throw CodexAppServerError.invalidResponse(
                method: "turn/start",
                reason: "missing turn.id"
            )
        }

        let handle = CodexTurnHandle(threadID: threadID, turnID: turnID)
        activeTurns[turnID] = handle
        return handle
    }

    /// Starts a fresh Codex thread when `threadID` is nil, or resumes the
    /// supplied thread, then returns a stream that ends with a typed result.
    /// Approval and user-input requests are yielded explicitly and are never
    /// answered automatically.
    public func runTurn(
        input: String,
        threadID: String? = nil,
        cwd: URL? = nil,
        model: String? = nil
    ) async throws -> AsyncThrowingStream<CodexTurnEvent, any Error> {
        try await runTurn(
            input: input,
            threadID: threadID,
            configuration: CodexThreadConfiguration(
                workingDirectory: cwd,
                model: model
            )
        )
    }

    public func runTurn(
        input: String,
        threadID: String? = nil,
        configuration: CodexThreadConfiguration
    ) async throws -> AsyncThrowingStream<CodexTurnEvent, any Error> {
        let thread: CodexThreadSession
        if let threadID {
            thread = try await resumeThread(id: threadID, configuration: configuration)
        } else {
            thread = try await startThread(configuration: configuration)
        }

        let handle = try await startTurn(threadID: thread.id, input: input)
        return makeTurnStream(for: handle)
    }

    private func threadParameters(
        _ configuration: CodexThreadConfiguration
    ) -> [String: JSONValue] {
        var parameters: [String: JSONValue] = [
            "serviceName": .string(configuration.serviceName),
        ]
        if let workingDirectory = configuration.workingDirectory {
            parameters["cwd"] = .string(workingDirectory.path(percentEncoded: false))
        }
        if let model = configuration.model {
            parameters["model"] = .string(model)
        }
        if let modelProvider = configuration.modelProvider {
            parameters["modelProvider"] = .string(modelProvider)
        }
        if let approvalPolicy = configuration.approvalPolicy {
            parameters["approvalPolicy"] = .string(approvalPolicy.rawValue)
        }
        if let sandbox = configuration.sandbox {
            parameters["sandbox"] = .string(sandbox.rawValue)
        }
        if let developerInstructions = configuration.developerInstructions {
            parameters["developerInstructions"] = .string(developerInstructions)
        }
        if let config = configuration.config {
            parameters["config"] = .object(config)
        }
        if let dynamicTools = configuration.dynamicTools {
            parameters["dynamicTools"] = .array(dynamicTools)
        }
        if let environments = configuration.environments {
            parameters["environments"] = .array(environments)
        }
        if let allowProviderModelFallback = configuration.allowProviderModelFallback {
            parameters["allowProviderModelFallback"] = .bool(allowProviderModelFallback)
        }
        return parameters
    }

    public func interrupt(_ handle: CodexTurnHandle) async throws {
        _ = try await request(
            method: "turn/interrupt",
            parameters: .object([
                "threadId": .string(handle.threadID),
                "turnId": .string(handle.turnID),
            ])
        )
    }

    /// Sends an explicit user-selected response to a pending server request.
    /// The caller owns the decision; the bridge never calls this by itself.
    public func respond(
        to interaction: CodexInteractionRequest,
        with result: JSONValue
    ) async throws {
        guard outstandingInteractions[interaction.requestID] == interaction else {
            throw CodexAppServerError.unknownInteraction(interaction.requestID)
        }

        try await transport.send(
            .object([
                "id": interaction.requestID.jsonValue,
                "result": result,
            ])
        )
        outstandingInteractions[interaction.requestID] = nil
    }

    /// Explicitly rejects or cancels every server interaction shape without
    /// granting capabilities. Unknown requests receive a JSON-RPC cancellation
    /// error rather than being left unresolved.
    public func denyOrCancel(_ interaction: CodexInteractionRequest) async throws {
        switch interaction.kind {
        case .commandApproval, .fileChangeApproval:
            try await respond(to: interaction, approval: .decline)
        case .permissionsApproval:
            try await respond(
                to: interaction,
                with: .object([
                    "permissions": .object([:]),
                    "scope": .string("turn"),
                ])
            )
        case .userInput:
            try await respond(to: interaction, with: .object(["answers": .object([:])]))
        case .mcpElicitation:
            try await respond(to: interaction, with: .object(["action": .string("cancel")]))
        case .unsupported:
            guard outstandingInteractions[interaction.requestID] == interaction else {
                throw CodexAppServerError.unknownInteraction(interaction.requestID)
            }
            try await transport.send(
                .object([
                    "id": interaction.requestID.jsonValue,
                    "error": .object([
                        "code": .integer(-32800),
                        "message": .string("Cancelled by chat-only Agent Relay worker"),
                    ]),
                ])
            )
            outstandingInteractions[interaction.requestID] = nil
        }
    }

    public func respond(
        to interaction: CodexInteractionRequest,
        approval decision: CodexApprovalDecision
    ) async throws {
        switch interaction.kind {
        case .commandApproval, .fileChangeApproval:
            try await respond(
                to: interaction,
                with: .object(["decision": .string(decision.rawValue)])
            )
        default:
            throw CodexAppServerError.invalidState(
                "This interaction does not accept a command or file approval decision."
            )
        }
    }

    public func respond(
        to interaction: CodexInteractionRequest,
        userInput answers: [String: [String]]
    ) async throws {
        guard interaction.kind == .userInput else {
            throw CodexAppServerError.invalidState(
                "This interaction is not a Codex user-input request."
            )
        }

        let encodedAnswers = answers.mapValues { values in
            JSONValue.object(["answers": .array(values.map(JSONValue.string))])
        }
        try await respond(
            to: interaction,
            with: .object(["answers": .object(encodedAnswers)])
        )
    }

    public func events() -> AsyncStream<CodexAppServerEvent> {
        let id = UUID()
        let pair = AsyncStream<CodexAppServerEvent>.makeStream()
        eventContinuations[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeEventContinuation(id)
            }
        }
        return pair.stream
    }

    /// Interrupts active turns before closing the local child process.
    public func terminate() async {
        switch state {
        case .ready:
            let turns = Array(activeTurns.values)
            for turn in turns {
                try? await interrupt(turn)
            }
        case .idle, .starting, .terminating, .closed:
            break
        }

        state = .terminating
        await transport.terminate()
        readerTask?.cancel()
        readerTask = nil
        finishAll(with: CodexAppServerError.connectionClosed("client terminated"))
        state = .closed
    }

    private func requireChatGPTManagedAccount() async throws {
        let summary: AccountSummary
        if let cachedAccountSummary {
            summary = cachedAccountSummary
        } else {
            summary = try await accountSummary()
        }

        guard summary.isChatGPTManaged else {
            throw CodexAppServerError.chatGPTManagedAuthenticationRequired(actual: summary.authType)
        }
    }

    private func request(method: String, parameters: JSONValue) async throws -> JSONValue {
        switch state {
        case .starting, .ready:
            break
        default:
            throw CodexAppServerError.invalidState(
                "Cannot send \(method) while Codex app-server is not connected."
            )
        }

        let requestID = JSONRPCID.integer(nextRequestID)
        nextRequestID += 1

        let pair = AsyncThrowingStream<JSONValue, any Error>.makeStream()
        pendingResponses[requestID] = pair.continuation

        do {
            try await transport.send(
                .object([
                    "method": .string(method),
                    "id": requestID.jsonValue,
                    "params": parameters,
                ])
            )
        } catch {
            pendingResponses[requestID] = nil
            pair.continuation.finish(throwing: error)
            throw error
        }

        do {
            let timeout = requestTimeout
            let result = try await withThrowingTaskGroup(of: JSONValue.self) { group in
                group.addTask {
                    for try await response in pair.stream {
                        return response
                    }
                    throw CodexAppServerError.connectionClosed(
                        "connection ended while waiting for \(method)"
                    )
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw CodexAppServerError.requestTimedOut(method)
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else {
                    throw CodexAppServerError.connectionClosed(
                        "connection ended while waiting for \(method)"
                    )
                }
                return first
            }
            pendingResponses[requestID] = nil
            pair.continuation.finish()
            return result
        } catch {
            pendingResponses[requestID] = nil
            pair.continuation.finish()
            throw error
        }
    }

    private func sendNotification(method: String, parameters: JSONValue) async throws {
        try await transport.send(
            .object([
                "method": .string(method),
                "params": parameters,
            ])
        )
    }

    private func receive(_ message: JSONValue) {
        guard let object = message.objectValue else {
            publish(.connectionClosed(message: "received a non-object JSON-RPC message"))
            return
        }

        let method = object["method"]?.stringValue
        let requestID = JSONRPCID(jsonValue: object["id"])

        if let method, let requestID {
            receiveServerRequest(
                id: requestID,
                method: method,
                parameters: object["params"] ?? .object([:])
            )
        } else if let requestID {
            receiveResponse(id: requestID, object: object)
        } else if let method {
            receiveNotification(
                method: method,
                parameters: object["params"] ?? .object([:])
            )
        } else {
            publish(.connectionClosed(message: "received an unrecognized JSON-RPC message"))
        }
    }

    private func receiveResponse(id: JSONRPCID, object: [String: JSONValue]) {
        guard let continuation = pendingResponses.removeValue(forKey: id) else {
            return
        }

        if let result = object["result"] {
            continuation.yield(result)
            continuation.finish()
            return
        }

        if let error = object["error"]?.objectValue {
            continuation.finish(
                throwing: CodexAppServerError.remote(
                    code: Int(error["code"]?.integerValue ?? -1),
                    message: error["message"]?.stringValue ?? "Unknown app-server error",
                    data: error["data"]
                )
            )
            return
        }

        continuation.finish(
            throwing: CodexAppServerError.invalidResponse(
                method: "request \(id)",
                reason: "missing result or error"
            )
        )
    }

    private func receiveServerRequest(id: JSONRPCID, method: String, parameters: JSONValue) {
        let kind: CodexInteractionRequest.Kind = switch method {
        case "item/commandExecution/requestApproval", "execCommandApproval":
            .commandApproval
        case "item/fileChange/requestApproval", "applyPatchApproval":
            .fileChangeApproval
        case "item/permissions/requestApproval":
            .permissionsApproval
        case "item/tool/requestUserInput":
            .userInput
        case "mcpServer/elicitation/request":
            .mcpElicitation
        default:
            .unsupported(method)
        }

        let interaction = CodexInteractionRequest(
            requestID: id,
            kind: kind,
            method: method,
            threadID: parameters["threadId"]?.stringValue,
            turnID: parameters["turnId"]?.stringValue,
            parameters: parameters
        )
        outstandingInteractions[id] = interaction
        publish(.interactionRequired(interaction))

        if let turnID = interaction.turnID {
            publishTurn(.interactionRequired(interaction), turnID: turnID)
        }
    }

    private func receiveNotification(method: String, parameters: JSONValue) {
        switch method {
        case "account/updated":
            let summary = parseAccountUpdatedNotification(parameters)
            cachedAccountSummary = summary
            publish(.accountUpdated(summary))

        case "item/agentMessage/delta":
            if let turnID = parameters["turnId"]?.stringValue,
               let itemID = parameters["itemId"]?.stringValue,
               let delta = parameters["delta"]?.stringValue
            {
                publishTurn(
                    .agentMessageDelta(itemID: itemID, delta: delta),
                    turnID: turnID
                )
            }
            publish(.notification(method: method, parameters: parameters))

        case "item/completed":
            receiveItemCompleted(parameters)
            publish(.notification(method: method, parameters: parameters))

        case "turn/completed":
            receiveTurnCompleted(parameters)
            publish(.notification(method: method, parameters: parameters))

        case "serverRequest/resolved":
            if let requestID = JSONRPCID(jsonValue: parameters["requestId"]) {
                outstandingInteractions[requestID] = nil
            }
            publish(.notification(method: method, parameters: parameters))

        default:
            publish(.notification(method: method, parameters: parameters))
        }
    }

    private func receiveItemCompleted(_ parameters: JSONValue) {
        guard let turnID = parameters["turnId"]?.stringValue,
              let item = parameters["item"]?.objectValue,
              item["type"]?.stringValue == "agentMessage",
              let itemID = item["id"]?.stringValue,
              let text = item["text"]?.stringValue
        else {
            return
        }

        let phase: CodexAgentMessage.Phase? = switch item["phase"]?.stringValue {
        case "commentary": .commentary
        case "final_answer": .finalAnswer
        case let value?: .other(value)
        case nil: nil
        }
        let message = CodexAgentMessage(id: itemID, text: text, phase: phase)

        var messages = completedAgentMessages[turnID, default: []]
        messages.removeAll { $0.id == itemID }
        messages.append(message)
        completedAgentMessages[turnID] = messages
        publishTurn(.agentMessageCompleted(message), turnID: turnID)
    }

    private func receiveTurnCompleted(_ parameters: JSONValue) {
        guard let threadID = parameters["threadId"]?.stringValue,
              let turn = parameters["turn"]?.objectValue,
              let turnID = turn["id"]?.stringValue
        else {
            return
        }

        let status = CodexTurnStatus(rawValue: turn["status"]?.stringValue ?? "") ?? .unknown
        let errorMessage = turn["error"]?["message"]?.stringValue
        let handle = activeTurns[turnID] ?? CodexTurnHandle(threadID: threadID, turnID: turnID)
        let result = CodexTurnResult(
            handle: handle,
            status: status,
            agentMessages: completedAgentMessages[turnID, default: []],
            errorMessage: errorMessage
        )

        activeTurns[turnID] = nil
        publishTurnCompletion(result)
    }

    private func makeTurnStream(
        for handle: CodexTurnHandle
    ) -> AsyncThrowingStream<CodexTurnEvent, any Error> {
        let pair = AsyncThrowingStream<CodexTurnEvent, any Error>.makeStream()
        turnContinuations[handle.turnID] = pair.continuation
        pair.continuation.yield(.started(handle))

        for event in bufferedTurnEvents.removeValue(forKey: handle.turnID) ?? [] {
            pair.continuation.yield(event)
        }

        if let result = completedTurns.removeValue(forKey: handle.turnID) {
            pair.continuation.yield(.completed(result))
            pair.continuation.finish()
            turnContinuations[handle.turnID] = nil
            completedAgentMessages[handle.turnID] = nil
        }

        pair.continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeTurnContinuation(handle.turnID)
            }
        }
        return pair.stream
    }

    private func publishTurn(_ event: CodexTurnEvent, turnID: String) {
        if let continuation = turnContinuations[turnID] {
            continuation.yield(event)
        } else {
            bufferedTurnEvents[turnID, default: []].append(event)
        }
    }

    private func publishTurnCompletion(_ result: CodexTurnResult) {
        let turnID = result.handle.turnID
        if let continuation = turnContinuations.removeValue(forKey: turnID) {
            continuation.yield(.completed(result))
            continuation.finish()
            completedAgentMessages[turnID] = nil
            bufferedTurnEvents[turnID] = nil
        } else {
            completedTurns[turnID] = result
        }
    }

    private func publish(_ event: CodexAppServerEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    private func readerEnded(error: (any Error)?) {
        switch state {
        case .terminating, .closed:
            return
        default:
            break
        }

        let message = error?.localizedDescription ?? "app-server reached end of stream"
        state = .closed
        publish(.connectionClosed(message: message))
        finishAll(with: CodexAppServerError.connectionClosed(message))
    }

    private func finishAll(with error: any Error) {
        for continuation in pendingResponses.values {
            continuation.finish(throwing: error)
        }
        pendingResponses.removeAll()

        for continuation in turnContinuations.values {
            continuation.finish(throwing: error)
        }
        turnContinuations.removeAll()

        for continuation in eventContinuations.values {
            continuation.finish()
        }
        eventContinuations.removeAll()
        activeTurns.removeAll()
        outstandingInteractions.removeAll()
    }

    private func removeEventContinuation(_ id: UUID) {
        eventContinuations[id] = nil
    }

    private func removeTurnContinuation(_ turnID: String) {
        turnContinuations[turnID] = nil
    }

    private func parseInitializeResponse(_ result: JSONValue) throws -> CodexAppServerInfo {
        guard let userAgent = result["userAgent"]?.stringValue,
              let platformFamily = result["platformFamily"]?.stringValue,
              let platformOS = result["platformOs"]?.stringValue
        else {
            throw CodexAppServerError.invalidResponse(
                method: "initialize",
                reason: "missing runtime identity fields"
            )
        }
        return CodexAppServerInfo(
            userAgent: userAgent,
            platformFamily: platformFamily,
            platformOS: platformOS
        )
    }

    private func parseAccountSummary(_ result: JSONValue) throws -> AccountSummary {
        guard let requiresAuthentication = result["requiresOpenaiAuth"]?.boolValue else {
            throw CodexAppServerError.invalidResponse(
                method: "account/read",
                reason: "missing requiresOpenaiAuth"
            )
        }

        guard let account = result["account"], account != .null else {
            return AccountSummary(
                authType: .none,
                planType: nil,
                requiresOpenAIAuthentication: requiresAuthentication
            )
        }

        guard let rawType = account["type"]?.stringValue else {
            throw CodexAppServerError.invalidResponse(
                method: "account/read",
                reason: "missing account.type"
            )
        }

        return AccountSummary(
            authType: accountAuthType(rawType),
            planType: account["planType"]?.stringValue.map(AccountSummary.PlanType.init(rawValue:)),
            requiresOpenAIAuthentication: requiresAuthentication
        )
    }

    private func parseAccountUpdatedNotification(_ parameters: JSONValue) -> AccountSummary {
        let rawAuthMode = parameters["authMode"]?.stringValue
        let authType = rawAuthMode.map(accountAuthType) ?? .none
        let plan = parameters["planType"]?.stringValue.map(AccountSummary.PlanType.init(rawValue:))
        return AccountSummary(
            authType: authType,
            planType: plan,
            requiresOpenAIAuthentication: cachedAccountSummary?.requiresOpenAIAuthentication ?? true
        )
    }

    private func accountAuthType(_ rawValue: String) -> AccountSummary.AuthType {
        switch rawValue {
        case "chatgpt": .chatGPT
        case "apiKey", "apikey": .apiKey
        case "amazonBedrock", "bedrockApiKey": .amazonBedrock
        default: .other(rawValue)
        }
    }

    private func parseThreadResponse(
        _ result: JSONValue,
        method: String
    ) throws -> CodexThreadSession {
        guard let threadID = result["thread"]?["id"]?.stringValue else {
            throw CodexAppServerError.invalidResponse(
                method: method,
                reason: "missing thread.id"
            )
        }

        let workingDirectory = result["cwd"]?.stringValue.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        return CodexThreadSession(
            id: threadID,
            model: result["model"]?.stringValue,
            workingDirectory: workingDirectory
        )
    }
}
