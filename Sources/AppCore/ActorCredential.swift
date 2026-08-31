import Foundation
import Security

public enum ActorCredential {
    public static let actorHeader = "X-Agent-Relay-Actor"
    public static let credentialHeader = "X-Agent-Relay-Actor-Token"
}

/// Stores independent random credentials for local actors. The shared bearer
/// token remains valid for API access, but it cannot be used to derive another
/// actor's credential.
public struct ActorCredentialStore: Sendable {
    public static let directoryName = "actor-credentials"

    private let directoryURL: URL

    public init(
        supportDirectory: URL,
        fileManager: FileManager = .default
    ) throws {
        self.directoryURL = supportDirectory.appendingPathComponent(
            Self.directoryName,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path(percentEncoded: false)
        )
    }

    public func load(actorID: String, fileManager: FileManager = .default) throws -> String? {
        let credentialURL = try url(for: actorID)
        let credentialPath = credentialURL.path(percentEncoded: false)
        guard fileManager.fileExists(atPath: credentialPath) else {
            return nil
        }
        let credential = try String(contentsOf: credentialURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !credential.isEmpty else {
            return nil
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: credentialPath
        )
        return credential
    }

    public func loadOrCreate(
        actorID: String,
        fileManager: FileManager = .default
    ) throws -> String {
        if let existing = try load(actorID: actorID, fileManager: fileManager) {
            return existing
        }

        let credential = try Self.generateCredential()
        let credentialURL = try url(for: actorID)
        let created = fileManager.createFile(
            atPath: credentialURL.path(percentEncoded: false),
            contents: Data(credential.utf8),
            attributes: [.posixPermissions: 0o600]
        )
        if created {
            return credential
        }
        guard let existing = try load(actorID: actorID, fileManager: fileManager) else {
            throw ActorCredentialStoreError.unableToCreateCredential(actorID)
        }
        return existing
    }

    public func validates(
        credential: String,
        actorID: String,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let expected = try? load(actorID: actorID, fileManager: fileManager) else {
            return false
        }
        return Self.constantTimeEqual(expected, credential)
    }

    public static func isValidActorID(_ actorID: String) -> Bool {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return (1...128).contains(actorID.count)
            && actorID.rangeOfCharacter(from: allowedCharacters.inverted) == nil
    }

    private func url(for actorID: String) throws -> URL {
        guard Self.isValidActorID(actorID) else {
            throw ActorCredentialStoreError.invalidActorID(actorID)
        }
        return directoryURL.appendingPathComponent(actorID, isDirectory: false)
    }

    private static func generateCredential(byteCount: Int = 32) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw ActorCredentialStoreError.randomGenerationFailed(Int(status))
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let lhsBytes = Array(lhs.utf8)
        let rhsBytes = Array(rhs.utf8)
        guard lhsBytes.count == rhsBytes.count else { return false }

        var difference: UInt8 = 0
        for index in lhsBytes.indices {
            difference |= lhsBytes[index] ^ rhsBytes[index]
        }
        return difference == 0
    }
}

public enum ActorCredentialStoreError: Error, Equatable, Sendable {
    case invalidActorID(String)
    case unableToCreateCredential(String)
    case randomGenerationFailed(Int)
}

public extension AppRuntimeConfiguration {
    static func actorCredentialStore(
        environment: [String: String],
        supportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> ActorCredentialStore {
        try ActorCredentialStore(
            supportDirectory: self.supportDirectory(
                environment: environment,
                overrideSupportDirectory: supportDirectory,
                fileManager: fileManager
            ),
            fileManager: fileManager
        )
    }

    static func loadOrCreateActorCredential(
        actorID: String,
        environment: [String: String],
        supportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> String {
        try actorCredentialStore(
            environment: environment,
            supportDirectory: supportDirectory,
            fileManager: fileManager
        ).loadOrCreate(actorID: actorID, fileManager: fileManager)
    }
}
