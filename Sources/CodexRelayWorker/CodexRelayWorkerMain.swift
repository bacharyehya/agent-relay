import CodexAppServer
import Darwin
import Foundation

@main
struct CodexRelayWorkerMain {
    static func main() async {
        do {
            let configuration = try WorkerConfiguration.live()
            let stateStore = try WorkerStateStore(
                supportDirectory: configuration.supportDirectory,
                actorID: configuration.actorID,
                threadID: configuration.threadID
            )
            let runtimeStatusStore = try WorkerRuntimeStatusStore(
                supportDirectory: configuration.supportDirectory,
                actorID: configuration.actorID,
                threadID: configuration.threadID
            )
            let instanceLock = try WorkerInstanceLock(
                supportDirectory: configuration.supportDirectory,
                actorID: configuration.actorID,
                threadID: configuration.threadID
            )
            let coreClient: any RelayCoreAPIClientProtocol
            switch configuration.transport {
            case .local:
                coreClient = RelayCoreAPIClient(
                    baseURL: configuration.coreServiceURL,
                    authToken: configuration.coreAuthToken,
                    actorID: configuration.actorID,
                    actorCredential: configuration.actorCredential
                )
            case .cloud:
                guard let cloudServiceURL = configuration.cloudServiceURL,
                      let cloudToken = configuration.cloudToken
                else {
                    throw WorkerConfigurationError.missingCloudTokenFile
                }
                coreClient = try RelayCloudWorkerAPIClient(
                    baseURL: cloudServiceURL,
                    token: cloudToken,
                    actorID: configuration.actorID,
                    deviceName: configuration.cloudDeviceName
                )
            }
            try await Self.runWorkerSessions(
                configuration: configuration,
                stateStore: stateStore,
                runtimeStatusStore: runtimeStatusStore,
                instanceLock: instanceLock,
                coreClient: coreClient
            )
        } catch {
            Self.writeError("CodexRelayWorker stopped: \(error.localizedDescription)")
            Darwin.exit(EXIT_FAILURE)
        }
    }

    private static func runWorkerSessions(
        configuration: WorkerConfiguration,
        stateStore: WorkerStateStore,
        runtimeStatusStore: WorkerRuntimeStatusStore,
        instanceLock: WorkerInstanceLock,
        coreClient: any RelayCoreAPIClientProtocol
    ) async throws {
        try? runtimeStatusStore.save(
            actorID: configuration.actorID,
            threadID: configuration.threadID,
            phase: .starting,
            detail: "Connecting to ChatGPT"
        )
        while !Task.isCancelled {
            let codexClient = CodexAppServerClient()
            let worker = try CodexRelayWorker(
                configuration: configuration,
                coreClient: coreClient,
                codexClient: codexClient,
                stateStore: stateStore,
                runtimeStatusStore: runtimeStatusStore,
                instanceLock: instanceLock
            )
            let account: AccountSummary
            do {
                account = try await worker.verifyChatGPTManagedAccount()
            } catch {
                try? runtimeStatusStore.save(
                    actorID: configuration.actorID,
                    threadID: configuration.threadID,
                    phase: .unavailable,
                    detail: "ChatGPT sign-in is unavailable"
                )
                try? await Self.postReadinessFailure(
                    configuration: configuration,
                    coreClient: coreClient
                )
                await codexClient.terminate()
                throw error
            }
            Self.writeStatus(
                "CodexRelayWorker ready as @\(configuration.actorID) in \(configuration.threadID) over \(configuration.transport.rawValue) using ChatGPT-managed Codex (plan: \(String(describing: account.planType)))."
            )
            try? runtimeStatusStore.save(
                actorID: configuration.actorID,
                threadID: configuration.threadID,
                phase: .ready,
                detail: "Watching for @mentions"
            )

            var restartCodexSession = false
            while !Task.isCancelled {
                var delayMilliseconds = configuration.pollIntervalMilliseconds
                do {
                    _ = try await worker.pollOnce()
                    try? runtimeStatusStore.save(
                        actorID: configuration.actorID,
                        threadID: configuration.threadID,
                        phase: .ready,
                        detail: "Watching for @mentions"
                    )
                } catch let error as RelayWorkerRecoveryError {
                    Self.writeError(
                        "CodexRelayWorker is restarting its bounded local Codex session: \(error.localizedDescription)"
                    )
                    try? runtimeStatusStore.save(
                        actorID: configuration.actorID,
                        threadID: configuration.threadID,
                        phase: .retrying,
                        detail: "Restarting the ChatGPT session"
                    )
                    restartCodexSession = true
                    break
                } catch {
                    Self.writeError(
                        "CodexRelayWorker poll failed and will retry safely: \(error.localizedDescription)"
                    )
                    try? runtimeStatusStore.save(
                        actorID: configuration.actorID,
                        threadID: configuration.threadID,
                        phase: .retrying,
                        detail: "Retrying after a safe failure"
                    )
                    delayMilliseconds = max(delayMilliseconds, 5_000)
                }
                try await Task.sleep(for: .milliseconds(delayMilliseconds))
            }

            await codexClient.terminate()
            guard restartCodexSession else { return }
            try await Task.sleep(for: .seconds(2))
        }
    }

    private static func writeStatus(_ message: String) {
        print(message)
    }

    private static func postReadinessFailure(
        configuration: WorkerConfiguration,
        coreClient: any RelayCoreAPIClientProtocol
    ) async throws {
        _ = try await coreClient.postMessage(
            threadID: configuration.threadID,
            request: RelayPostMessageRequest(
                actorID: configuration.actorID,
                body: "Unavailable: @\(configuration.actorID) could not start its ChatGPT-managed Codex session, so it exited without processing mentions. @bash can restart it after checking the ChatGPT sign-in and local Codex installation.",
                format: .markdown,
                replyToMessageID: nil,
                mentionedActorIDs: ["bash"]
            ),
            idempotencyKey: "codex-worker-\(WorkerStateStore.safeComponent(configuration.actorID))-readiness-failure-v1-\(WorkerStateStore.safeComponent(configuration.threadID))"
        )
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
