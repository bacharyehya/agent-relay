import AppCore
import Foundation
import RelayCloudClient
import RelayCloudKit

actor RelayCloudKitWorkerAPIClient: RelayCoreAPIClientProtocol {
    private let mailbox: RelayCloudKitWorkerMailbox
    private let actorID: String

    init(actorID: String, supportDirectory: URL) throws {
        self.actorID = actorID
        self.mailbox = try RelayCloudKitWorkerMailbox(supportDirectory: supportDirectory)
    }

    func getMessages(
        threadID: String,
        limit: Int,
        before: MessageCursor?
    ) async throws -> [Message] {
        let messages = try await mailbox.messages(
            roomID: threadID,
            beforeSequence: before?.sequence,
            beforeMessageID: before?.messageID,
            limit: limit
        )
        return messages.map(Self.message)
    }

    func postMessage(
        threadID: String,
        request: RelayPostMessageRequest,
        idempotencyKey: String
    ) async throws -> Message {
        guard request.actorID == actorID else {
            throw RelayCloudWorkerAPIError.actorMismatch(expected: actorID, actual: request.actorID)
        }
        let posted = try await mailbox.enqueueMessage(
            roomID: threadID,
            actorID: actorID,
            body: request.body,
            format: request.format,
            replyToMessageID: request.replyToMessageID,
            mentionedActorIDs: request.mentionedActorIDs,
            idempotencyKey: idempotencyKey
        )
        return Self.message(posted)
    }

    private static func message(_ message: RelayCloudMessage) -> Message {
        Message(
            id: message.id,
            sequence: message.sequence,
            threadID: message.roomID,
            actorID: message.actorID,
            body: message.body,
            format: message.format,
            replyToMessageID: message.replyToMessageID,
            mentionedActorIDs: message.mentionedActorIDs,
            createdAt: message.createdAt
        )
    }
}
