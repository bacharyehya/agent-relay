import AppCore
import Foundation

enum WorkerConfigurationError: LocalizedError, Equatable {
    case missingActorID
    case invalidPollInterval(String)

    var errorDescription: String? {
        switch self {
        case .missingActorID:
            "AGENT_RELAY_ACTOR_ID is required to start a Codex relay worker."
        case let .invalidPollInterval(value):
            "AGENT_RELAY_POLL_INTERVAL_MS must be an integer from 100 through 60000, not \(value)."
        }
    }
}

struct WorkerConfiguration: Equatable, Sendable {
    static let defaultThreadID = "thread-general"
    static let defaultPollIntervalMilliseconds = 1_500

    let actorID: String
    let threadID: String
    let pollIntervalMilliseconds: Int
    let codexWorkingDirectory: URL?
    let codexModel: String?
    let supportDirectory: URL
    let coreServiceURL: URL
    let coreAuthToken: String
    let actorCredential: String

    static func live(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> WorkerConfiguration {
        let actorID = environment["AGENT_RELAY_ACTOR_ID"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !actorID.isEmpty else {
            throw WorkerConfigurationError.missingActorID
        }

        let threadID = nonempty(environment["AGENT_RELAY_THREAD_ID"])
            ?? defaultThreadID
        let rawPollInterval = nonempty(environment["AGENT_RELAY_POLL_INTERVAL_MS"])
        let pollInterval: Int
        if let rawPollInterval {
            guard let parsed = Int(rawPollInterval), (100...60_000).contains(parsed) else {
                throw WorkerConfigurationError.invalidPollInterval(rawPollInterval)
            }
            pollInterval = parsed
        } else {
            pollInterval = defaultPollIntervalMilliseconds
        }

        let cwd = nonempty(environment["AGENT_RELAY_CODEX_CWD"]).map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let supportDirectory = try AppRuntimeConfiguration.supportDirectory(environment: environment)
        return WorkerConfiguration(
            actorID: actorID,
            threadID: threadID,
            pollIntervalMilliseconds: pollInterval,
            codexWorkingDirectory: cwd,
            codexModel: nonempty(environment["AGENT_RELAY_CODEX_MODEL"]),
            supportDirectory: supportDirectory,
            coreServiceURL: AppRuntimeConfiguration.coreServiceURL(environment: environment),
            coreAuthToken: try AppRuntimeConfiguration.loadOrCreateAuthToken(
                environment: environment,
                supportDirectory: supportDirectory
            ),
            actorCredential: try AppRuntimeConfiguration.loadOrCreateActorCredential(
                actorID: actorID,
                environment: environment,
                supportDirectory: supportDirectory
            )
        )
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}
