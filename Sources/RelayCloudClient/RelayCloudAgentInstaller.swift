import AppCore
import Foundation

public enum RelayCloudAgentInstallerError: LocalizedError, Equatable {
    case invalidActorID
    case invalidAgentToken
    case differentRelayAlreadyConfigured
    case unreadableConfiguration

    public var errorDescription: String? {
        switch self {
        case .invalidActorID:
            "The agent ID is not safe for a local worker configuration."
        case .invalidAgentToken:
            "The Relay service did not return a valid agent credential."
        case .differentRelayAlreadyConfigured:
            "This Mac already has local agents configured for a different Relay workspace."
        case .unreadableConfiguration:
            "Agent Relay could not read its local cloud worker configuration."
        }
    }
}

public struct RelayCloudAgentRuntimeConfiguration: Codable, Equatable, Sendable {
    public let serverURL: URL
    public let roomID: String
    public let actorIDs: [String]

    public init(serverURL: URL, roomID: String, actorIDs: [String]) {
        self.serverURL = serverURL
        self.roomID = roomID
        self.actorIDs = actorIDs
    }
}

public enum RelayCloudAgentInstaller {
    public static let directoryName = "CloudAgents"
    public static let configurationFileName = "runtime.json"

    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> RelayCloudAgentRuntimeConfiguration? {
        let directory = try directory(environment: environment, fileManager: fileManager)
        let url = directory.appendingPathComponent(configurationFileName, isDirectory: false)
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        guard let data = fileManager.contents(atPath: url.path(percentEncoded: false)),
              let configuration = try? JSONDecoder().decode(RelayCloudAgentRuntimeConfiguration.self, from: data)
        else {
            throw RelayCloudAgentInstallerError.unreadableConfiguration
        }
        return configuration
    }

    @discardableResult
    public static func install(
        serverURL: URL,
        roomID: String,
        actorID: String,
        token: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> RelayCloudAgentRuntimeConfiguration {
        guard isSafeActorID(actorID) else { throw RelayCloudAgentInstallerError.invalidActorID }
        guard token.hasPrefix("relay_agent_"), token.count >= 32 else {
            throw RelayCloudAgentInstallerError.invalidAgentToken
        }
        let directory = try directory(environment: environment, fileManager: fileManager)
        let existing = try load(environment: environment, fileManager: fileManager)
        if let existing,
           (existing.serverURL != serverURL || existing.roomID != roomID)
        {
            throw RelayCloudAgentInstallerError.differentRelayAlreadyConfigured
        }

        let tokenURL = directory.appendingPathComponent("\(actorID).token", isDirectory: false)
        try secureWrite(Data(token.utf8), to: tokenURL, fileManager: fileManager)

        var actorIDs = existing?.actorIDs ?? []
        if !actorIDs.contains(actorID) { actorIDs.append(actorID) }
        actorIDs.sort()
        let configuration = RelayCloudAgentRuntimeConfiguration(
            serverURL: serverURL,
            roomID: roomID,
            actorIDs: actorIDs
        )
        let configurationURL = directory.appendingPathComponent(configurationFileName, isDirectory: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try secureWrite(encoder.encode(configuration), to: configurationURL, fileManager: fileManager)
        return configuration
    }

    public static func tokenFileURL(
        actorID: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard isSafeActorID(actorID) else { throw RelayCloudAgentInstallerError.invalidActorID }
        return try directory(environment: environment, fileManager: fileManager)
            .appendingPathComponent("\(actorID).token", isDirectory: false)
    }

    private static func directory(
        environment: [String: String],
        fileManager: FileManager
    ) throws -> URL {
        let supportDirectory = try AppRuntimeConfiguration.supportDirectory(
            environment: environment,
            fileManager: fileManager
        )
        let directory = supportDirectory.appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path(percentEncoded: false)
        )
        return directory
    }

    private static func isSafeActorID(_ actorID: String) -> Bool {
        guard !actorID.isEmpty, actorID.count <= 64 else { return false }
        return actorID.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
        }
    }

    private static func secureWrite(
        _ data: Data,
        to destination: URL,
        fileManager: FileManager
    ) throws {
        let temporary = destination
            .deletingLastPathComponent()
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
