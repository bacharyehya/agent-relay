import AppCore
import Foundation
import RelayCloudClient

enum RelayCloudWorkerAPIError: LocalizedError, Equatable {
    case actorMismatch(expected: String, actual: String)
    case missingSequence

    var errorDescription: String? {
        switch self {
        case let .actorMismatch(expected, actual):
            "The cloud credential belongs to @\(expected), but the worker tried to post as @\(actual)."
        case .missingSequence:
            "The cloud message cursor did not include its durable sequence number."
        }
    }
}

actor RelayCloudWorkerAPIClient: RelayCoreAPIClientProtocol {
    private let api: RelayCloudAPI
    private let actorID: String
    private let deviceName: String

    init(baseURL: URL, token: String, actorID: String, deviceName: String) throws {
        self.api = try RelayCloudAPI(baseURL: baseURL, token: token)
        self.actorID = actorID
        self.deviceName = deviceName
    }

    func getMessages(
        threadID: String,
        limit: Int,
        before: MessageCursor?
    ) async throws -> [Message] {
        if before != nil, before?.sequence == nil {
            throw RelayCloudWorkerAPIError.missingSequence
        }
        _ = try? await api.updatePresence(state: "online", deviceName: deviceName)
        let messages = try await api.messages(
            roomID: threadID,
            before: before?.sequence,
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
        let posted = try await api.postMessage(
            roomID: threadID,
            message: RelayPostMessage(
                body: request.body,
                format: request.format,
                replyToMessageID: request.replyToMessageID,
                mentionedActorIDs: request.mentionedActorIDs
            ),
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
