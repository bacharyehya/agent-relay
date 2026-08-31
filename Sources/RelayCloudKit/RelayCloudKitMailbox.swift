import AppCore
import CryptoKit
import Foundation
import RelayCloudClient

public struct RelayCloudKitAgentRuntimeConfiguration: Codable, Equatable, Sendable {
    public let roomID: String
    public let actorIDs: [String]

    public init(roomID: String, actorIDs: [String]) {
        self.roomID = roomID
        self.actorIDs = actorIDs
    }
}

public enum RelayCloudKitAgentInstallerError: LocalizedError, Equatable {
    case invalidActorID
    case unreadableConfiguration

    public var errorDescription: String? {
        switch self {
        case .invalidActorID:
            "The agent ID may contain only letters, numbers, hyphens, and underscores."
        case .unreadableConfiguration:
            "Agent Relay could not read its local CloudKit agent configuration."
        }
    }
}

public enum RelayCloudKitMailboxError: LocalizedError, Equatable {
    case idempotencyConflict

    public var errorDescription: String? {
        switch self {
        case .idempotencyConflict:
            "That agent turn was already recorded with different content."
        }
    }
}

public enum RelayCloudKitPaths {
    public static let directoryName = "CloudKit"
    public static let cacheFileName = "relay-cache.json"
    public static let outboxDirectoryName = "Outbox"
    public static let agentConfigurationFileName = "agents.json"

    public static func directory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        supportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let support = try AppRuntimeConfiguration.supportDirectory(
            environment: environment,
            overrideSupportDirectory: supportDirectory,
            fileManager: fileManager
        )
        let directory = support.appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }

    public static func cacheURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        supportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        try directory(
            environment: environment,
            supportDirectory: supportDirectory,
            fileManager: fileManager
        ).appendingPathComponent(cacheFileName, isDirectory: false)
    }

    public static func outboxDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        supportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let outbox = try directory(
            environment: environment,
            supportDirectory: supportDirectory,
            fileManager: fileManager
        ).appendingPathComponent(outboxDirectoryName, isDirectory: true)
        try fileManager.createDirectory(
            at: outbox,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return outbox
    }
}

public enum RelayCloudKitAgentInstaller {
    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        supportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> RelayCloudKitAgentRuntimeConfiguration? {
        let url = try RelayCloudKitPaths.directory(
            environment: environment,
            supportDirectory: supportDirectory,
            fileManager: fileManager
        ).appendingPathComponent(RelayCloudKitPaths.agentConfigurationFileName)
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        guard let data = fileManager.contents(atPath: url.path(percentEncoded: false)),
              let configuration = try? RelayCloudKitPersistence.decoder.decode(
                RelayCloudKitAgentRuntimeConfiguration.self,
                from: data
              )
        else {
            throw RelayCloudKitAgentInstallerError.unreadableConfiguration
        }
        return configuration
    }

    @discardableResult
    public static func install(
        roomID: String = "thread-general",
        actorID: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        supportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> RelayCloudKitAgentRuntimeConfiguration {
        guard isSafeActorID(actorID) else {
            throw RelayCloudKitAgentInstallerError.invalidActorID
        }
        let directory = try RelayCloudKitPaths.directory(
            environment: environment,
            supportDirectory: supportDirectory,
            fileManager: fileManager
        )
        var actorIDs = try load(
            environment: environment,
            supportDirectory: supportDirectory,
            fileManager: fileManager
        )?.actorIDs ?? []
        if !actorIDs.contains(actorID) { actorIDs.append(actorID) }
        actorIDs.sort()
        let configuration = RelayCloudKitAgentRuntimeConfiguration(
            roomID: roomID,
            actorIDs: actorIDs
        )
        let url = directory.appendingPathComponent(RelayCloudKitPaths.agentConfigurationFileName)
        try RelayCloudKitPersistence.atomicWrite(
            RelayCloudKitPersistence.encoder.encode(configuration),
            to: url,
            fileManager: fileManager
        )
        return configuration
    }

    public static func isSafeActorID(_ actorID: String) -> Bool {
        guard !actorID.isEmpty, actorID.count <= 64 else { return false }
        return actorID.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
        }
    }
}

struct RelayCloudKitOutboxMessage: Codable, Equatable, Sendable {
    let id: String
    let sequence: Int
    let roomID: String
    let actorID: String
    let body: String
    let format: MessageFormat
    let replyToMessageID: String?
    let mentionedActorIDs: [String]
    let createdAt: Date

    var message: RelayCloudMessage {
        RelayCloudMessage(
            id: id,
            sequence: sequence,
            roomID: roomID,
            threadID: roomID,
            actorID: actorID,
            body: body,
            format: format,
            replyToMessageID: replyToMessageID,
            mentionedActorIDs: mentionedActorIDs,
            createdAt: createdAt,
            editedAt: nil
        )
    }
}

public actor RelayCloudKitWorkerMailbox {
    private let cacheURL: URL
    private let outboxDirectory: URL
    private let fileManager: FileManager

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        supportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        self.fileManager = fileManager
        self.cacheURL = try RelayCloudKitPaths.cacheURL(
            environment: environment,
            supportDirectory: supportDirectory,
            fileManager: fileManager
        )
        self.outboxDirectory = try RelayCloudKitPaths.outboxDirectory(
            environment: environment,
            supportDirectory: supportDirectory,
            fileManager: fileManager
        )
    }

    public func messages(
        roomID: String,
        beforeSequence: Int?,
        beforeMessageID: String?,
        limit: Int
    ) throws -> [RelayCloudMessage] {
        guard limit > 0 else { return [] }
        let cache = try RelayCloudKitPersistence.loadCache(from: cacheURL, fileManager: fileManager)
        var messages = RelayCloudKitSnapshotBuilder
            .snapshot(from: cache, currentActorID: "bash")
            .messages
            .filter { $0.roomID == roomID }
        if let beforeSequence {
            messages = messages.filter { message in
                message.sequence < beforeSequence
                    || (message.sequence == beforeSequence
                        && message.id < (beforeMessageID ?? message.id))
            }
        }
        return Array(messages.suffix(limit))
    }

    @discardableResult
    public func enqueueMessage(
        roomID: String,
        actorID: String,
        body: String,
        format: MessageFormat,
        replyToMessageID: String?,
        mentionedActorIDs: [String],
        idempotencyKey: String
    ) throws -> RelayCloudMessage {
        guard RelayCloudKitAgentInstaller.isSafeActorID(actorID) else {
            throw RelayCloudKitAgentInstallerError.invalidActorID
        }
        guard !body.isEmpty,
              body.count <= RelayCloudKitLimits.messageBodyCharacters,
              mentionedActorIDs.count <= RelayCloudKitLimits.mentionedActors
        else {
            throw RelayCloudKitDatabaseError.messageTooLong
        }
        let stableInput = "\(actorID)\u{1f}\(roomID)\u{1f}\(idempotencyKey)"
        let digest = SHA256.hash(data: Data(stableInput.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let messageID = "agent-\(digest)"
        let destination = outboxDirectory.appendingPathComponent("\(digest).json")

        if let existing = try existingMessage(id: messageID, outboxURL: destination) {
            guard existing.roomID == roomID,
                  existing.actorID == actorID,
                  existing.body == body,
                  existing.format == format,
                  existing.replyToMessageID == replyToMessageID,
                  existing.mentionedActorIDs == mentionedActorIDs
            else {
                throw RelayCloudKitMailboxError.idempotencyConflict
            }
            return existing
        }

        let sequenceDate = Date()
        let createdAt = Date(
            timeIntervalSince1970: (
                sequenceDate.timeIntervalSince1970 * 1_000
            ).rounded(.down) / 1_000
        )
        let outbox = RelayCloudKitOutboxMessage(
            id: messageID,
            sequence: RelayCloudKitSequence.value(at: sequenceDate),
            roomID: roomID,
            actorID: actorID,
            body: body,
            format: format,
            replyToMessageID: replyToMessageID,
            mentionedActorIDs: mentionedActorIDs,
            createdAt: createdAt
        )
        try RelayCloudKitPersistence.atomicWrite(
            RelayCloudKitPersistence.encoder.encode(outbox),
            to: destination,
            fileManager: fileManager
        )
        return outbox.message
    }

    private func existingMessage(id: String, outboxURL: URL) throws -> RelayCloudMessage? {
        if fileManager.fileExists(atPath: outboxURL.path(percentEncoded: false)) {
            let data = try Data(contentsOf: outboxURL)
            return try RelayCloudKitPersistence.decoder.decode(
                RelayCloudKitOutboxMessage.self,
                from: data
            ).message
        }

        let cache = try RelayCloudKitPersistence.loadCache(from: cacheURL, fileManager: fileManager)
        guard let entity = cache.entities[RelayCloudKitRecordName.message(id)] else { return nil }
        return RelayCloudKitEntityFactory.decode(RelayCloudMessage.self, from: entity)
    }
}

enum RelayCloudKitSequence {
    static func value(at date: Date = Date()) -> Int {
        Int((date.timeIntervalSince1970 * 1_000_000).rounded(.down))
    }
}

enum RelayCloudKitPersistence {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()

    static func loadCache(from url: URL, fileManager: FileManager = .default) throws -> RelayCloudKitCache {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return RelayCloudKitCache()
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(RelayCloudKitCache.self, from: data)
    }

    static func atomicWrite(_ data: Data, to destination: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        guard fileManager.createFile(
            atPath: temporary.path(percentEncoded: false),
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path(percentEncoded: false)
            )
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }
}
