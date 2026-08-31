import AppCore
import Foundation

enum WorkerConfigurationError: LocalizedError, Equatable {
    case missingActorID
    case invalidPollInterval(String)
    case invalidTransport(String)
    case invalidCloudURL(String)
    case missingCloudTokenFile
    case insecureCloudTokenFile(String)
    case unreadableCloudTokenFile(String)

    var errorDescription: String? {
        switch self {
        case .missingActorID:
            "AGENT_RELAY_ACTOR_ID is required to start a Codex relay worker."
        case let .invalidPollInterval(value):
            "AGENT_RELAY_POLL_INTERVAL_MS must be an integer from 100 through 60000, not \(value)."
        case let .invalidTransport(value):
            "AGENT_RELAY_TRANSPORT must be local, cloudkit, or cloud, not \(value)."
        case let .invalidCloudURL(value):
            "AGENT_RELAY_CLOUD_URL must be a valid HTTPS URL, not \(value)."
        case .missingCloudTokenFile:
            "AGENT_RELAY_CLOUD_TOKEN_FILE is required for a cloud worker."
        case let .insecureCloudTokenFile(path):
            "The cloud worker token file must not be readable by group or other users: \(path)."
        case let .unreadableCloudTokenFile(path):
            "The cloud worker token file is missing or unreadable: \(path)."
        }
    }
}

enum RelayWorkerTransport: String, Equatable, Sendable {
    case local
    case cloudKit = "cloudkit"
    case cloud
}

struct WorkerConfiguration: Equatable, Sendable {
    static let defaultThreadID = "thread-general"
    static let defaultPollIntervalMilliseconds = 1_500
    static let defaultCloudPollIntervalMilliseconds = 15_000

    static func defaultPollIntervalMilliseconds(for transport: RelayWorkerTransport) -> Int {
        switch transport {
        case .local, .cloudKit:
            defaultPollIntervalMilliseconds
        case .cloud:
            defaultCloudPollIntervalMilliseconds
        }
    }

    let actorID: String
    let transport: RelayWorkerTransport
    let threadID: String
    let pollIntervalMilliseconds: Int
    let codexWorkingDirectory: URL?
    let codexModel: String?
    let supportDirectory: URL
    let coreServiceURL: URL
    let coreAuthToken: String
    let actorCredential: String
    let cloudServiceURL: URL?
    let cloudToken: String?
    let cloudDeviceName: String

    static func live(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> WorkerConfiguration {
        let actorID = environment["AGENT_RELAY_ACTOR_ID"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !actorID.isEmpty else {
            throw WorkerConfigurationError.missingActorID
        }

        let rawTransport = nonempty(environment["AGENT_RELAY_TRANSPORT"]) ?? RelayWorkerTransport.local.rawValue
        guard let transport = RelayWorkerTransport(rawValue: rawTransport.lowercased()) else {
            throw WorkerConfigurationError.invalidTransport(rawTransport)
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
            pollInterval = defaultPollIntervalMilliseconds(for: transport)
        }

        let cwd = nonempty(environment["AGENT_RELAY_CODEX_CWD"]).map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let supportDirectory = try AppRuntimeConfiguration.supportDirectory(environment: environment)
        let coreAuthToken: String
        let actorCredential: String
        let cloudServiceURL: URL?
        let cloudToken: String?
        if transport == .cloud {
            let rawURL = nonempty(environment["AGENT_RELAY_CLOUD_URL"]) ?? ""
            guard let url = URL(string: rawURL), url.scheme?.lowercased() == "https", url.host != nil else {
                throw WorkerConfigurationError.invalidCloudURL(rawURL)
            }
            guard let tokenPath = nonempty(environment["AGENT_RELAY_CLOUD_TOKEN_FILE"]) else {
                throw WorkerConfigurationError.missingCloudTokenFile
            }
            let attributes: [FileAttributeKey: Any]
            do {
                attributes = try FileManager.default.attributesOfItem(atPath: tokenPath)
            } catch {
                throw WorkerConfigurationError.unreadableCloudTokenFile(tokenPath)
            }
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o777
            guard permissions & 0o077 == 0 else {
                throw WorkerConfigurationError.insecureCloudTokenFile(tokenPath)
            }
            guard let data = FileManager.default.contents(atPath: tokenPath),
                  let token = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  token.hasPrefix("relay_agent_")
            else {
                throw WorkerConfigurationError.unreadableCloudTokenFile(tokenPath)
            }
            cloudServiceURL = url
            cloudToken = token
            coreAuthToken = ""
            actorCredential = ""
        } else if transport == .local {
            cloudServiceURL = nil
            cloudToken = nil
            coreAuthToken = try AppRuntimeConfiguration.loadOrCreateAuthToken(
                environment: environment,
                supportDirectory: supportDirectory
            )
            actorCredential = try AppRuntimeConfiguration.loadOrCreateActorCredential(
                actorID: actorID,
                environment: environment,
                supportDirectory: supportDirectory
            )
        } else {
            cloudServiceURL = nil
            cloudToken = nil
            coreAuthToken = ""
            actorCredential = ""
        }
        return WorkerConfiguration(
            actorID: actorID,
            transport: transport,
            threadID: threadID,
            pollIntervalMilliseconds: pollInterval,
            codexWorkingDirectory: cwd,
            codexModel: nonempty(environment["AGENT_RELAY_CODEX_MODEL"]),
            supportDirectory: supportDirectory,
            coreServiceURL: AppRuntimeConfiguration.coreServiceURL(environment: environment),
            coreAuthToken: coreAuthToken,
            actorCredential: actorCredential,
            cloudServiceURL: cloudServiceURL,
            cloudToken: cloudToken,
            cloudDeviceName: nonempty(environment["AGENT_RELAY_CLOUD_DEVICE_NAME"])
                ?? ProcessInfo.processInfo.hostName
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
