import XCTest
@testable import AppCore
@testable import MacAppSupport

@MainActor
final class ThreadDetailViewModelTests: XCTestCase {
    func test_accept_handoff_updates_local_card_state() async throws {
        let client = StubAppAPIClient()
        let model = ThreadDetailViewModel(client: client, threadID: "thread-1")

        await model.acceptHandoff(id: "handoff-1")

        XCTAssertEqual(model.handoffs.first?.status, .accepted)
    }

    func test_create_handoff_uses_requested_target_actor() async throws {
        let recorder = CreateHandoffRecorder()
        let client = StubAppAPIClient(createRecorder: recorder)
        let model = ThreadDetailViewModel(client: client, threadID: "thread-1")

        await model.createHandoff(
            title: "Need help",
            summary: "Summarize the blocker",
            ask: "Review the failing route",
            assignedTo: "claude"
        )

        let request = await recorder.lastRequest
        XCTAssertEqual(request?.assignedTo, "claude")
    }

    func test_create_handoff_records_error_when_request_fails() async {
        let client = StubAppAPIClient(createError: AppAPIClientError.httpStatus(401, "Missing bearer token"))
        let model = ThreadDetailViewModel(client: client, threadID: "thread-1")

        await model.createHandoff(
            title: "Need help",
            summary: "Summarize the blocker",
            ask: "Review the failing route",
            assignedTo: "claude"
        )

        XCTAssertNotNil(model.errorMessage)
    }

    func test_post_message_posts_as_bash_with_mentions_and_reply_context() async {
        let recorder = PostMessageRecorder()
        let client = StubAppAPIClient(postMessageRecorder: recorder)
        let model = ThreadDetailViewModel(client: client, threadID: "thread-1")

        let posted = await model.postMessage(
            body: "  Please review this @codex, then ask @claude. @codex  ",
            replyToMessageID: "message-parent"
        )

        let recorded = await recorder.lastRequest
        XCTAssertTrue(posted)
        XCTAssertEqual(recorded?.threadID, "thread-1")
        XCTAssertEqual(recorded?.request.actorID, "bash")
        XCTAssertEqual(recorded?.request.body, "Please review this @codex, then ask @claude. @codex")
        XCTAssertEqual(recorded?.request.replyToMessageID, "message-parent")
        XCTAssertEqual(recorded?.request.mentionedActorIDs, ["codex", "claude"])
        XCTAssertEqual(model.threadContext?.messages.last?.actorID, "bash")
    }

    func test_refresh_messages_replaces_the_visible_history() async {
        let message = Message(
            id: "message-agent",
            threadID: "thread-1",
            actorID: "codex",
            body: "I found the issue."
        )
        let client = StubAppAPIClient(fetchedMessages: [message])
        let model = ThreadDetailViewModel(
            client: client,
            threadID: "thread-1",
            initialContext: AppThreadContext(
                thread: .example(id: "thread-1"),
                messages: [],
                handoffs: []
            )
        )

        await model.refreshMessages()

        XCTAssertEqual(model.threadContext?.messages, [message])
    }
}

private struct StubAppAPIClient: AppAPIClientProtocol {
    let createRecorder: CreateHandoffRecorder?
    let createError: Error?
    let postMessageRecorder: PostMessageRecorder?
    let fetchedMessages: [Message]

    init(
        createRecorder: CreateHandoffRecorder? = nil,
        createError: Error? = nil,
        postMessageRecorder: PostMessageRecorder? = nil,
        fetchedMessages: [Message] = []
    ) {
        self.createRecorder = createRecorder
        self.createError = createError
        self.postMessageRecorder = postMessageRecorder
        self.fetchedMessages = fetchedMessages
    }

    func fetchHealth() async throws -> AppHealth {
        AppHealth(status: "ok")
    }

    func fetchInbox(actorID: String) async throws -> [Handoff] {
        []
    }

    func fetchRecents() async throws -> [AppRecentItem] {
        []
    }

    func search(query: String) async throws -> [AppSearchResult] {
        []
    }

    func fetchProjects() async throws -> [Project] {
        []
    }

    func fetchProjectThreads(projectID: String) async throws -> [AppCore.Thread] {
        []
    }

    func fetchThreadContext(threadID: String, mode: String) async throws -> AppThreadContext {
        AppThreadContext(
            thread: .example(id: threadID),
            messages: [],
            handoffs: [.example(id: "handoff-1", threadID: threadID)]
        )
    }

    func fetchThreadMessages(threadID: String, limit: Int, before: MessageCursor?) async throws -> [Message] {
        fetchedMessages
    }

    func postMessage(threadID: String, request: AppPostMessageRequest) async throws -> Message {
        await postMessageRecorder?.record(threadID: threadID, request: request)
        var message = Message(
            id: "message-posted",
            threadID: threadID,
            actorID: request.actorID,
            body: request.body,
            format: request.format
        )
        message.replyToMessageID = request.replyToMessageID
        message.mentionedActorIDs = request.mentionedActorIDs
        return message
    }

    func createHandoff(_ request: AppCreateHandoffRequest) async throws -> Handoff {
        if let createError {
            throw createError
        }
        await createRecorder?.record(request)
        return Handoff(
            id: "handoff-created",
            threadID: request.threadID,
            title: request.title,
            summary: request.summary,
            ask: request.ask,
            priority: request.priority,
            createdBy: request.createdBy,
            assignedTo: request.assignedTo,
            sourceRefs: request.sourceRefs
        )
    }

    func updateHandoff(id: String, status: HandoffStatus, resolution: String?) async throws -> Handoff {
        var handoff = Handoff.example(id: id, status: status)
        handoff.resolution = resolution
        return handoff
    }
}

actor CreateHandoffRecorder {
    private(set) var lastRequest: AppCreateHandoffRequest?

    func record(_ request: AppCreateHandoffRequest) {
        lastRequest = request
    }
}

actor PostMessageRecorder {
    private(set) var lastRequest: (threadID: String, request: AppPostMessageRequest)?

    func record(threadID: String, request: AppPostMessageRequest) {
        lastRequest = (threadID, request)
    }
}
