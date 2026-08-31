import AppCore
import Foundation

struct AgentRuntimeStatusReader: Sendable {
    private let supportDirectory: URL?
    private let now: @Sendable () -> Date

    init(
        supportDirectory: URL? = try? AppRuntimeConfiguration.supportDirectory(
            environment: ProcessInfo.processInfo.environment
        ),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.supportDirectory = supportDirectory
        self.now = now
    }

    func load() -> [AgentRuntimeStatus] {
        guard let supportDirectory else { return [] }
        let directory = supportDirectory.appendingPathComponent("workers", isDirectory: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let currentTime = now()

        return RelayAgentProfile.known.compactMap { profile in
            let url = directory.appendingPathComponent(
                AgentRuntimeStatus.fileName(
                    actorID: profile.id,
                    threadID: "thread-general"
                )
            )
            guard let data = try? Data(contentsOf: url),
                  let status = try? decoder.decode(AgentRuntimeStatus.self, from: data)
            else {
                return nil
            }

            guard currentTime.timeIntervalSince(status.updatedAt) <= 12 else {
                return AgentRuntimeStatus(
                    actorID: status.actorID,
                    threadID: status.threadID,
                    phase: .unavailable,
                    detail: "Worker stopped reporting",
                    updatedAt: status.updatedAt
                )
            }
            return status
        }
    }
}
