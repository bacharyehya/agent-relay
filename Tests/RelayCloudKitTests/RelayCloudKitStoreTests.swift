import AppCore
import Foundation
import RelayCloudClient
import XCTest
@testable import RelayCloudKit

final class RelayCloudKitStoreTests: XCTestCase {
    func test_snapshot_builds_rooms_messages_and_exact_unread_counts() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let workspace = RelayWorkspace(id: "main", name: "Bash's Agents")
        let owner = RelayCloudActor(
            id: "bash",
            type: .human,
            displayName: "Bash",
            role: "owner",
            status: .active
        )
        let room = RelayCloudRoom(
            id: "thread-general",
            name: "general",
            title: "General",
            topic: "",
            isArchived: false,
            updatedAt: now
        )
        let first = message(id: "one", sequence: 100, date: now)
        let second = message(id: "two", sequence: 1_000_000, date: now.addingTimeInterval(1))
        let receipt = RelayCloudKitReadReceipt(
            actorID: "bash",
            roomID: room.id,
            lastReadSequence: first.sequence,
            updatedAt: now
        )

        var cache = RelayCloudKitCache()
        for entity in [
            try RelayCloudKitEntityFactory.entity(
                id: RelayCloudKitRecordName.workspace(workspace.id),
                kind: .workspace,
                value: workspace
            ),
            try RelayCloudKitEntityFactory.entity(
                id: RelayCloudKitRecordName.actor(owner.id),
                kind: .actor,
                value: owner
            ),
            try RelayCloudKitEntityFactory.entity(
                id: RelayCloudKitRecordName.room(room.id),
                kind: .room,
                value: room
            ),
            try RelayCloudKitEntityFactory.entity(
                id: RelayCloudKitRecordName.message(first.id),
                kind: .message,
                value: first
            ),
            try RelayCloudKitEntityFactory.entity(
                id: RelayCloudKitRecordName.message(second.id),
                kind: .message,
                value: second
            ),
            try RelayCloudKitEntityFactory.entity(
                id: RelayCloudKitRecordName.readReceipt(actorID: "bash", roomID: room.id),
                kind: .readReceipt,
                value: receipt
            ),
        ] {
            cache.entities[entity.id] = entity
        }

        let snapshot = RelayCloudKitSnapshotBuilder.snapshot(from: cache, currentActorID: "bash")

        XCTAssertEqual(snapshot.workspace, workspace)
        XCTAssertEqual(snapshot.messages.map(\.id), ["one", "two"])
        XCTAssertEqual(snapshot.rooms.first?.latestSequence, second.sequence)
        XCTAssertEqual(snapshot.rooms.first?.lastReadSequence, first.sequence)
        XCTAssertEqual(snapshot.rooms.first?.unreadCount, 1)
    }

    func test_agent_mailbox_is_durable_and_idempotent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = try RelayCloudKitWorkerMailbox(supportDirectory: directory)

        let first = try await mailbox.enqueueMessage(
            roomID: "thread-general",
            actorID: "codex-main",
            body: "Ready.",
            format: .markdown,
            replyToMessageID: nil,
            mentionedActorIDs: ["bash"],
            idempotencyKey: "same-turn"
        )
        let replay = try await mailbox.enqueueMessage(
            roomID: "thread-general",
            actorID: "codex-main",
            body: "Ready.",
            format: .markdown,
            replyToMessageID: nil,
            mentionedActorIDs: ["bash"],
            idempotencyKey: "same-turn"
        )
        let outbox = try RelayCloudKitPaths.outboxDirectory(supportDirectory: directory)
        let files = try FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil)

        XCTAssertEqual(first.id, replay.id)
        XCTAssertEqual(first.createdAt, replay.createdAt)
        XCTAssertEqual(files.filter { $0.pathExtension == "json" }.count, 1)
    }

    func test_agent_mailbox_replays_from_cache_and_rejects_changed_content() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = try RelayCloudKitWorkerMailbox(supportDirectory: directory)

        let first = try await mailbox.enqueueMessage(
            roomID: "thread-general",
            actorID: "codex-main",
            body: "Ready.",
            format: .markdown,
            replyToMessageID: nil,
            mentionedActorIDs: ["bash"],
            idempotencyKey: "durable-turn"
        )
        var cache = RelayCloudKitCache()
        cache.entities[RelayCloudKitRecordName.message(first.id)] = try RelayCloudKitEntityFactory.entity(
            id: RelayCloudKitRecordName.message(first.id),
            kind: .message,
            value: first,
            modifiedAt: first.createdAt
        )
        let cacheURL = try RelayCloudKitPaths.cacheURL(supportDirectory: directory)
        try RelayCloudKitPersistence.atomicWrite(
            RelayCloudKitPersistence.encoder.encode(cache),
            to: cacheURL
        )
        let outbox = try RelayCloudKitPaths.outboxDirectory(supportDirectory: directory)
        for url in try FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: url)
        }

        let replay = try await mailbox.enqueueMessage(
            roomID: "thread-general",
            actorID: "codex-main",
            body: "Ready.",
            format: .markdown,
            replyToMessageID: nil,
            mentionedActorIDs: ["bash"],
            idempotencyKey: "durable-turn"
        )
        XCTAssertEqual(replay, first)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil).isEmpty)

        do {
            _ = try await mailbox.enqueueMessage(
                roomID: "thread-general",
                actorID: "codex-main",
                body: "Changed.",
                format: .markdown,
                replyToMessageID: nil,
                mentionedActorIDs: ["bash"],
                idempotencyKey: "durable-turn"
            )
            XCTFail("Expected changed idempotent content to be rejected")
        } catch let error as RelayCloudKitMailboxError {
            XCTAssertEqual(error, .idempotencyConflict)
        }
    }

    func test_read_receipt_conflicts_never_move_backwards() throws {
        let earlier = Date(timeIntervalSince1970: 1_800_000_000)
        let later = earlier.addingTimeInterval(60)
        let local = try RelayCloudKitEntityFactory.entity(
            id: "read:bash:thread-general",
            kind: .readReceipt,
            value: RelayCloudKitReadReceipt(
                actorID: "bash",
                roomID: "thread-general",
                lastReadSequence: 500,
                updatedAt: earlier
            ),
            modifiedAt: earlier
        )
        let remote = try RelayCloudKitEntityFactory.entity(
            id: "read:bash:thread-general",
            kind: .readReceipt,
            value: RelayCloudKitReadReceipt(
                actorID: "bash",
                roomID: "thread-general",
                lastReadSequence: 100,
                updatedAt: later
            ),
            modifiedAt: later
        )

        XCTAssertTrue(RelayCloudKitConflictPolicy.localWins(local, over: remote))
        XCTAssertFalse(RelayCloudKitConflictPolicy.localWins(remote, over: local))
    }

    func test_cached_mode_allows_transient_status_but_not_signed_out_account() {
        XCTAssertTrue(
            RelayCloudKitFailurePolicy.allowsCachedMode(
                for: RelayCloudKitDatabaseError.iCloudStatusUnknown
            )
        )
        XCTAssertFalse(
            RelayCloudKitFailurePolicy.allowsCachedMode(
                for: RelayCloudKitDatabaseError.iCloudAccountUnavailable
            )
        )
    }

    func test_agent_installer_adds_without_overwriting_existing_agents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try RelayCloudKitAgentInstaller.install(
            actorID: "codex-main",
            supportDirectory: directory
        )
        let configuration = try RelayCloudKitAgentInstaller.install(
            actorID: "codex-research",
            supportDirectory: directory
        )

        XCTAssertEqual(configuration.roomID, "thread-general")
        XCTAssertEqual(configuration.actorIDs, ["codex-main", "codex-research"])
    }

    func test_agent_mailbox_rejects_unsafe_identity_and_oversized_payload() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = try RelayCloudKitWorkerMailbox(supportDirectory: directory)

        do {
            _ = try await mailbox.enqueueMessage(
                roomID: "thread-general",
                actorID: "../not-safe",
                body: "hello",
                format: .markdown,
                replyToMessageID: nil,
                mentionedActorIDs: [],
                idempotencyKey: "unsafe"
            )
            XCTFail("Expected unsafe actor ID to be rejected")
        } catch let error as RelayCloudKitAgentInstallerError {
            XCTAssertEqual(error, .invalidActorID)
        }

        do {
            _ = try await mailbox.enqueueMessage(
                roomID: "thread-general",
                actorID: "codex-main",
                body: String(repeating: "x", count: RelayCloudKitLimits.messageBodyCharacters + 1),
                format: .markdown,
                replyToMessageID: nil,
                mentionedActorIDs: [],
                idempotencyKey: "too-large"
            )
            XCTFail("Expected oversized payload to be rejected")
        } catch let error as RelayCloudKitDatabaseError {
            XCTAssertEqual(error, .messageTooLong)
        }
    }

    private func message(id: String, sequence: Int, date: Date) -> RelayCloudMessage {
        RelayCloudMessage(
            id: id,
            sequence: sequence,
            roomID: "thread-general",
            threadID: "thread-general",
            actorID: "bash",
            body: id,
            format: .markdown,
            replyToMessageID: nil,
            mentionedActorIDs: [],
            createdAt: date,
            editedAt: nil
        )
    }
}
