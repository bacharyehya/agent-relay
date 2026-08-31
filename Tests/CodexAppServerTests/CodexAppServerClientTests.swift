import Foundation
import XCTest
@testable import CodexAppServer

final class CodexAppServerClientTests: XCTestCase {
    func test_accountSummaryUsesManagedChatGPTAuthWithoutExposingAccountDetails() async throws {
        let transport = ScriptedTransport()
        let client = CodexAppServerClient(transport: transport)

        let summary = try await client.accountSummary()

        XCTAssertEqual(summary.authType, .chatGPT)
        XCTAssertEqual(summary.planType, .pro)
        XCTAssertTrue(summary.isChatGPTManaged)
        XCTAssertTrue(summary.isPro)

        let sentMethods = await transport.sentMethods()
        XCTAssertEqual(Array(sentMethods.prefix(3)), ["initialize", "initialized", "account/read"])
        await client.terminate()
    }

    func test_runTurnStreamsCompletedAgentMessagesAndFinalText() async throws {
        let transport = ScriptedTransport()
        let client = CodexAppServerClient(transport: transport)

        let stream = try await client.runTurn(
            input: "Give me the result.",
            cwd: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
            model: "gpt-test"
        )
        var received: [CodexTurnEvent] = []
        for try await event in stream {
            received.append(event)
        }

        XCTAssertTrue(received.contains(.agentMessageDelta(itemID: "message-final", delta: "Done")))
        XCTAssertTrue(
            received.contains(
                .agentMessageCompleted(
                    CodexAgentMessage(
                        id: "message-final",
                        text: "Done.",
                        phase: .finalAnswer
                    )
                )
            )
        )

        guard case let .completed(result) = received.last else {
            return XCTFail("Expected a completed turn event")
        }
        XCTAssertEqual(result.status, .completed)
        XCTAssertEqual(result.finalText, "Done.")
        await client.terminate()
    }

    func test_approvalRequestIsSurfacedAndNeverAutoApproved() async throws {
        let transport = ScriptedTransport(includeApprovalRequest: true)
        let client = CodexAppServerClient(transport: transport)
        let stream = try await client.runTurn(input: "Run a command.")
        var iterator = stream.makeAsyncIterator()

        let firstEvent = try await iterator.next()
        XCTAssertEqual(
            firstEvent,
            .started(CodexTurnHandle(threadID: "thread-1", turnID: "turn-1"))
        )

        let secondEvent = try await iterator.next()
        guard case let .interactionRequired(interaction) = secondEvent else {
            return XCTFail("Expected an explicit approval request")
        }
        XCTAssertEqual(interaction.kind, .commandApproval)
        let respondedBeforeDecision = await transport.hasResponse(for: .string("approval-1"))
        XCTAssertFalse(respondedBeforeDecision)

        try await client.respond(to: interaction, approval: .decline)
        let respondedAfterDecision = await transport.hasResponse(for: .string("approval-1"))
        XCTAssertTrue(respondedAfterDecision)
        await client.terminate()
    }

    func test_denyOrCancelSendsExplicitDeclineForCommandApproval() async throws {
        let transport = ScriptedTransport(includeApprovalRequest: true)
        let client = CodexAppServerClient(transport: transport)
        let stream = try await client.runTurn(input: "Run a command.")
        var iterator = stream.makeAsyncIterator()

        _ = try await iterator.next()
        guard case let .interactionRequired(interaction) = try await iterator.next() else {
            return XCTFail("Expected an explicit approval request")
        }

        try await client.denyOrCancel(interaction)

        let response = await transport.response(for: .string("approval-1"))
        XCTAssertEqual(response?["result"]?["decision"], .string("decline"))
        await client.terminate()
    }

    func test_requestDeadlineFailsClosedWhenAppServerDoesNotRespond() async throws {
        let transport = ScriptedTransport(unansweredMethods: ["account/read"])
        let client = CodexAppServerClient(
            transport: transport,
            requestTimeout: .milliseconds(20)
        )

        do {
            _ = try await client.accountSummary()
            XCTFail("Expected the bounded request deadline to fire")
        } catch let error as CodexAppServerError {
            XCTAssertEqual(error, .requestTimedOut("account/read"))
        }
        await client.terminate()
    }

    func test_nonChatGPTAccountCannotStartAThread() async throws {
        let transport = ScriptedTransport(accountType: "apiKey")
        let client = CodexAppServerClient(transport: transport)

        do {
            _ = try await client.startThread()
            XCTFail("Expected ChatGPT-managed authentication enforcement")
        } catch let error as CodexAppServerError {
            XCTAssertEqual(
                error,
                .chatGPTManagedAuthenticationRequired(actual: .apiKey)
            )
        }

        let sentMethods = await transport.sentMethods()
        XCTAssertFalse(sentMethods.contains("thread/start"))
        await client.terminate()
    }

    func test_restrictedThreadConfigurationIsSentToStartAndResume() async throws {
        let transport = ScriptedTransport()
        let client = CodexAppServerClient(transport: transport)
        let configuration = CodexThreadConfiguration(
            workingDirectory: URL(fileURLWithPath: "/tmp/chat-only", isDirectory: true),
            model: "gpt-test",
            modelProvider: "openai",
            approvalPolicy: .never,
            sandbox: .readOnly,
            developerInstructions: "Never use tools.",
            config: [
                "features": .object([
                    "shell_tool": .bool(false),
                    "unified_exec": .bool(false),
                ]),
            ],
            dynamicTools: [],
            environments: [],
            serviceName: "relay-test",
            allowProviderModelFallback: false
        )

        _ = try await client.startThread(configuration: configuration)
        _ = try await client.resumeThread(id: "thread-1", configuration: configuration)

        for method in ["thread/start", "thread/resume"] {
            let receivedParameters = await transport.parameters(for: method)
            let parameters = try XCTUnwrap(receivedParameters)
            XCTAssertEqual(parameters["modelProvider"], .string("openai"))
            XCTAssertEqual(parameters["approvalPolicy"], .string("never"))
            XCTAssertEqual(parameters["sandbox"], .string("read-only"))
            XCTAssertEqual(parameters["developerInstructions"], .string("Never use tools."))
            XCTAssertEqual(
                parameters["config"]?["features"]?["shell_tool"],
                .bool(false)
            )
            XCTAssertEqual(parameters["dynamicTools"], .array([]))
            XCTAssertEqual(parameters["environments"], .array([]))
            XCTAssertEqual(parameters["allowProviderModelFallback"], .bool(false))
        }
        await client.terminate()
    }

    func test_processTransportEnvironmentUsesAnAllowlist() {
        let sanitized = CodexProcessTransport.sanitizedEnvironment([
            "HOME": "/Users/test",
            "PATH": "/usr/bin",
            "CODEX_HOME": "/Users/test/.codex",
            "OPENAI_API_KEY": "must-not-escape",
            "CODEX_API_KEY": "must-not-escape",
            "OPENAI_BASE_URL": "https://custom.invalid",
            "AWS_SECRET_ACCESS_KEY": "must-not-escape",
            "HTTPS_PROXY": "https://user:password@proxy.invalid",
        ])

        XCTAssertEqual(sanitized["HOME"], "/Users/test")
        XCTAssertEqual(sanitized["PATH"], "/usr/bin")
        XCTAssertEqual(sanitized["CODEX_HOME"], "/Users/test/.codex")
        XCTAssertNil(sanitized["OPENAI_API_KEY"])
        XCTAssertNil(sanitized["CODEX_API_KEY"])
        XCTAssertNil(sanitized["OPENAI_BASE_URL"])
        XCTAssertNil(sanitized["AWS_SECRET_ACCESS_KEY"])
        XCTAssertNil(sanitized["HTTPS_PROXY"])
    }

    func test_processTransportResolvesAnInstalledAppBinaryWithoutFinderPath() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-transport-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let executable = temporaryDirectory.appendingPathComponent("codex")
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: executable.path(percentEncoded: false),
                contents: Data()
            )
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executable.path(percentEncoded: false)
        )

        let resolved = CodexProcessTransport.resolveInstalledCodexURL(
            candidateURLs: [
                temporaryDirectory.appendingPathComponent("missing"),
                executable,
            ]
        )

        XCTAssertEqual(resolved, executable)
    }

    func test_configuredMCPServerNamesReturnsOnlySortedIdentifiers() async throws {
        let transport = ScriptedTransport()
        let client = CodexAppServerClient(transport: transport)

        let names = try await client.configuredMCPServerNames(
            cwd: URL(fileURLWithPath: "/tmp/chat-only", isDirectory: true)
        )

        XCTAssertEqual(names, ["node_repl", "private-server"])
        let receivedParameters = await transport.parameters(for: "config/read")
        XCTAssertEqual(receivedParameters?["includeLayers"], .bool(false))
        await client.terminate()
    }
}

private actor ScriptedTransport: CodexAppServerTransport {
    private let accountType: String
    private let includeApprovalRequest: Bool
    private let unansweredMethods: Set<String>
    private let stream: AsyncThrowingStream<JSONValue, any Error>
    private let continuation: AsyncThrowingStream<JSONValue, any Error>.Continuation
    private var sent: [JSONValue] = []

    init(
        accountType: String = "chatgpt",
        includeApprovalRequest: Bool = false,
        unansweredMethods: Set<String> = []
    ) {
        self.accountType = accountType
        self.includeApprovalRequest = includeApprovalRequest
        self.unansweredMethods = unansweredMethods
        let pair = AsyncThrowingStream<JSONValue, any Error>.makeStream()
        self.stream = pair.stream
        self.continuation = pair.continuation
    }

    func start() {}

    func messages() -> AsyncThrowingStream<JSONValue, any Error> {
        stream
    }

    func send(_ message: JSONValue) {
        sent.append(message)
        guard let method = message["method"]?.stringValue,
              let id = message["id"]
        else {
            return
        }
        guard !unansweredMethods.contains(method) else { return }

        switch method {
        case "initialize":
            respond(
                id: id,
                result: .object([
                    "codexHome": .string("/redacted"),
                    "userAgent": .string("codex-test"),
                    "platformFamily": .string("unix"),
                    "platformOs": .string("macos"),
                ])
            )

        case "account/read":
            let account: JSONValue
            if accountType == "chatgpt" {
                account = .object([
                    "type": .string("chatgpt"),
                    "email": .string("must-not-escape@example.com"),
                    "planType": .string("pro"),
                    "accessToken": .string("must-not-escape"),
                ])
            } else {
                account = .object(["type": .string(accountType)])
            }
            respond(
                id: id,
                result: .object([
                    "account": account,
                    "requiresOpenaiAuth": .bool(true),
                ])
            )

        case "config/read":
            respond(
                id: id,
                result: .object([
                    "config": .object([
                        "mcp_servers": .object([
                            "private-server": .object([
                                "bearer_token": .string("must-not-escape"),
                            ]),
                            "node_repl": .object([
                                "command": .string("must-not-escape"),
                            ]),
                        ]),
                    ]),
                    "origins": .object([:]),
                ])
            )

        case "thread/start", "thread/resume":
            respond(
                id: id,
                result: .object([
                    "thread": .object(["id": .string("thread-1")]),
                    "model": .string("gpt-test"),
                    "cwd": .string("/tmp/project"),
                ])
            )

        case "turn/start":
            respond(
                id: id,
                result: .object([
                    "turn": .object([
                        "id": .string("turn-1"),
                        "status": .string("inProgress"),
                        "items": .array([]),
                    ]),
                ])
            )

            if includeApprovalRequest {
                continuation.yield(
                    .object([
                        "id": .string("approval-1"),
                        "method": .string("item/commandExecution/requestApproval"),
                        "params": .object([
                            "threadId": .string("thread-1"),
                            "turnId": .string("turn-1"),
                            "itemId": .string("command-1"),
                            "command": .string("echo safe"),
                        ]),
                    ])
                )
            } else {
                continuation.yield(
                    .object([
                        "method": .string("item/agentMessage/delta"),
                        "params": .object([
                            "threadId": .string("thread-1"),
                            "turnId": .string("turn-1"),
                            "itemId": .string("message-final"),
                            "delta": .string("Done"),
                        ]),
                    ])
                )
                continuation.yield(
                    .object([
                        "method": .string("item/completed"),
                        "params": .object([
                            "threadId": .string("thread-1"),
                            "turnId": .string("turn-1"),
                            "completedAtMs": .integer(1),
                            "item": .object([
                                "type": .string("agentMessage"),
                                "id": .string("message-final"),
                                "text": .string("Done."),
                                "phase": .string("final_answer"),
                            ]),
                        ]),
                    ])
                )
                continuation.yield(
                    .object([
                        "method": .string("turn/completed"),
                        "params": .object([
                            "threadId": .string("thread-1"),
                            "turn": .object([
                                "id": .string("turn-1"),
                                "status": .string("completed"),
                                "items": .array([]),
                            ]),
                        ]),
                    ])
                )
            }

        case "turn/interrupt":
            respond(id: id, result: .object([:]))

        default:
            respond(id: id, result: .object([:]))
        }
    }

    func terminate() {
        continuation.finish()
    }

    func sentMethods() -> [String] {
        sent.compactMap { $0["method"]?.stringValue }
    }

    func hasResponse(for id: JSONRPCID) -> Bool {
        sent.contains { message in
            JSONRPCID(jsonValue: message["id"]) == id && message["method"] == nil
        }
    }

    func response(for id: JSONRPCID) -> JSONValue? {
        sent.first { message in
            JSONRPCID(jsonValue: message["id"]) == id && message["method"] == nil
        }
    }

    func parameters(for method: String) -> JSONValue? {
        sent.first { $0["method"]?.stringValue == method }?["params"]
    }

    private func respond(id: JSONValue, result: JSONValue) {
        continuation.yield(.object(["id": id, "result": result]))
    }
}
