import Darwin
import Foundation

struct PendingRelayResponse: Codable, Equatable, Sendable {
    let body: String
    let mentionedActorIDs: [String]
}

struct RelayWorkerState: Codable, Equatable, Sendable {
    var processedMessageIDs: Set<String> = []
    var codexThreadID: String?
    var pendingResponses: [String: PendingRelayResponse] = [:]

    private enum CodingKeys: String, CodingKey {
        case processedMessageIDs
        case codexThreadID
        case pendingResponses
    }

    init(
        processedMessageIDs: Set<String> = [],
        codexThreadID: String? = nil,
        pendingResponses: [String: PendingRelayResponse] = [:]
    ) {
        self.processedMessageIDs = processedMessageIDs
        self.codexThreadID = codexThreadID
        self.pendingResponses = pendingResponses
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        processedMessageIDs = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .processedMessageIDs
        ) ?? []
        codexThreadID = try container.decodeIfPresent(String.self, forKey: .codexThreadID)
        pendingResponses = try container.decodeIfPresent(
            [String: PendingRelayResponse].self,
            forKey: .pendingResponses
        ) ?? [:]
    }
}

struct WorkerStateStore: Sendable {
    let stateURL: URL

    init(supportDirectory: URL, actorID: String, threadID: String) throws {
        let workerDirectory = supportDirectory.appendingPathComponent("workers", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workerDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        stateURL = workerDirectory.appendingPathComponent(
            "\(Self.safeComponent(actorID))--\(Self.safeComponent(threadID)).json",
            isDirectory: false
        )
    }

    func load() throws -> RelayWorkerState {
        guard FileManager.default.fileExists(
            atPath: stateURL.path(percentEncoded: false)
        ) else {
            return RelayWorkerState()
        }
        let data = try Data(contentsOf: stateURL)
        return try JSONDecoder().decode(RelayWorkerState.self, from: data)
    }

    func save(_ state: RelayWorkerState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(state)
        data.append(0x0A)
        try data.write(to: stateURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: stateURL.path(percentEncoded: false)
        )
    }

    static func safeComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }
        let result = scalars.joined()
        return result.isEmpty ? "actor" : result
    }
}

enum WorkerInstanceLockError: LocalizedError, Equatable {
    case alreadyRunning(actorID: String, threadID: String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .alreadyRunning(actorID, threadID):
            "A Codex relay worker is already running for \(actorID) in \(threadID)."
        case let .unavailable(message):
            "Unable to acquire the Codex relay worker lock: \(message)"
        }
    }
}

/// A process-scoped advisory lock. The small PID file remains for diagnosis,
/// while the kernel releases the actual lock automatically after crashes.
final class WorkerInstanceLock: @unchecked Sendable {
    private let descriptor: Int32

    init(supportDirectory: URL, actorID: String, threadID: String) throws {
        let workerDirectory = supportDirectory.appendingPathComponent("workers", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workerDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let lockURL = workerDirectory.appendingPathComponent(
            "\(WorkerStateStore.safeComponent(actorID))--\(WorkerStateStore.safeComponent(threadID)).lock",
            isDirectory: false
        )

        let descriptor = Darwin.open(
            lockURL.path(percentEncoded: false),
            O_RDWR | O_CREAT,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw WorkerInstanceLockError.unavailable(String(cString: strerror(errno)))
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            if errno == EWOULDBLOCK {
                throw WorkerInstanceLockError.alreadyRunning(actorID: actorID, threadID: threadID)
            }
            throw WorkerInstanceLockError.unavailable(String(cString: strerror(errno)))
        }

        self.descriptor = descriptor
        _ = ftruncate(descriptor, 0)
        let pid = "\(getpid())\n"
        pid.withCString { pointer in
            _ = Darwin.write(descriptor, pointer, strlen(pointer))
        }
        _ = fsync(descriptor)
    }

    deinit {
        _ = flock(descriptor, LOCK_UN)
        _ = Darwin.close(descriptor)
    }
}
