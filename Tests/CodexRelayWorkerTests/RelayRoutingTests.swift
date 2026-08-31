import AppCore
import CodexAppServer
import Foundation
import Testing
@testable import CodexRelayWorker

@Test
func humanMentionAlwaysTriggersEvenBelowAnAgentChain() {
    let first = testMessage(id: "a1", actorID: "agent-a", replyTo: nil, mentions: ["agent-b"])
    let second = testMessage(id: "a2", actorID: "agent-b", replyTo: "a1", mentions: ["agent-c"])
    let third = testMessage(id: "a3", actorID: "agent-c", replyTo: "a2", mentions: ["agent-d"])
    let human = testMessage(id: "h1", actorID: "bash", replyTo: "a3", mentions: ["agent-d"])

    #expect(
        RelayRouting.decision(
            for: human,
            actorID: "agent-d",
            messages: [first, second, third, human]
        ) == .respond
    )
}

@Test
func thirdConsecutiveAgentMessageStopsTheNextReply() {
    let human = testMessage(id: "h1", actorID: "bash", replyTo: nil, mentions: ["agent-a"])
    let first = testMessage(id: "a1", actorID: "agent-a", replyTo: "h1", mentions: ["agent-b"])
    let second = testMessage(id: "a2", actorID: "agent-b", replyTo: "a1", mentions: ["agent-c"])
    let third = testMessage(id: "a3", actorID: "agent-c", replyTo: "a2", mentions: ["agent-d"])

    #expect(
        RelayRouting.consecutiveAgentDepth(
            for: third,
            messages: [human, first, second, third]
        ) == 3
    )
    #expect(
        RelayRouting.decision(
            for: third,
            actorID: "agent-d",
            messages: [human, first, second, third]
        ) == .stopAgentChain
    )
}

@Test
func unresolvedAgentAncestorFailsClosedAtTheDepthLimit() {
    let message = testMessage(
        id: "a3",
        actorID: "agent-c",
        replyTo: "missing-ancestor",
        mentions: ["agent-d"]
    )

    #expect(
        RelayRouting.decision(
            for: message,
            actorID: "agent-d",
            messages: [message]
        ) == .stopAgentChain
    )
}

@Test
func secondConsecutiveAgentMessageCanTriggerAReply() {
    let human = testMessage(id: "h1", actorID: "bash", replyTo: nil, mentions: ["agent-a"])
    let first = testMessage(id: "a1", actorID: "agent-a", replyTo: "h1", mentions: ["agent-b"])
    let second = testMessage(id: "a2", actorID: "agent-b", replyTo: "a1", mentions: ["agent-c"])

    #expect(
        RelayRouting.decision(
            for: second,
            actorID: "agent-c",
            messages: [human, first, second]
        ) == .respond
    )
}

@Test
func agentMentionsAreParsedAndDeduplicated() {
    #expect(
        RelayRouting.mentionedActorIDs(
            in: "Please ask @reviewer, then @codex-main. @reviewer already knows."
        ) == ["reviewer", "codex-main"]
    )
}

@Test
func promptUsesBoundedRecentRoomContextAndAlwaysIncludesTriggerBody() {
    let messages = (0..<35).map { index in
        testMessage(
            id: "m\(index)",
            actorID: index.isMultiple(of: 2) ? "bash" : "agent-a",
            body: "body-\(index)",
            replyTo: index == 0 ? nil : "m\(index - 1)",
            mentions: []
        )
    }
    let prompt = RelayPromptBuilder.prompt(
        actorID: "agent-b",
        trigger: messages[0],
        recentMessages: messages
    )

    #expect(prompt.contains("<triggering_message actor=\"bash\">\nbody-0"))
    #expect(!prompt.components(separatedBy: "<room_context>").last!.contains("body-4"))
    #expect(prompt.contains("body-5"))
    #expect(prompt.contains("body-34"))
    #expect(prompt.contains("You are @agent-b"))
    #expect(prompt.contains("untrusted conversation content"))
}

@Test
func stateRoundTripsProcessedPendingAndCodexThread() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-relay-worker-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let store = try WorkerStateStore(
        supportDirectory: temporaryDirectory,
        actorID: "codex/main",
        threadID: "thread-general"
    )
    let expected = RelayWorkerState(
        processedMessageIDs: ["message-1", "message-2"],
        codexThreadID: "codex-thread-1",
        pendingResponses: [
            "message-3": PendingRelayResponse(
                body: "ready to retry",
                mentionedActorIDs: ["reviewer"]
            ),
        ]
    )

    try store.save(expected)

    #expect(try store.load() == expected)
    let attributes = try FileManager.default.attributesOfItem(
        atPath: store.stateURL.path(percentEncoded: false)
    )
    #expect(attributes[.posixPermissions] as? NSNumber == NSNumber(value: 0o600))
}

@Test
func secondWorkerInstanceForSameActorAndRoomIsRejected() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-relay-lock-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let first = try WorkerInstanceLock(
        supportDirectory: temporaryDirectory,
        actorID: "codex-main",
        threadID: "thread-general"
    )
    do {
        _ = try WorkerInstanceLock(
            supportDirectory: temporaryDirectory,
            actorID: "codex-main",
            threadID: "thread-general"
        )
        Issue.record("Expected the duplicate worker lock to be rejected")
    } catch {
        #expect(
            error as? WorkerInstanceLockError
                == .alreadyRunning(actorID: "codex-main", threadID: "thread-general")
        )
    }
    withExtendedLifetime(first) {}
}

@Test
func boundedTurnStreamTimesOutInsteadOfHangingForever() async {
    let pair = AsyncThrowingStream<CodexTurnEvent, any Error>.makeStream()
    defer { pair.continuation.finish() }
    let bounded = CodexRelayWorker.boundedTurnEvents(
        pair.stream,
        timeout: .milliseconds(20)
    )
    var iterator = bounded.makeAsyncIterator()

    do {
        _ = try await iterator.next()
        Issue.record("Expected the bounded turn deadline to fire")
    } catch {
        #expect(error as? RelayWorkerTurnError == .timedOut)
    }
}

private func testMessage(
    id: String,
    actorID: String,
    body: String = "hello",
    replyTo: String?,
    mentions: [String]
) -> Message {
    Message(
        id: id,
        threadID: "thread-general",
        actorID: actorID,
        body: body,
        replyToMessageID: replyTo,
        mentionedActorIDs: mentions,
        createdAt: Date(timeIntervalSince1970: 1)
    )
}
