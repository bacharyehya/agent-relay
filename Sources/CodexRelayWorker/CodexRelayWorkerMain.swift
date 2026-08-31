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
            let instanceLock = try WorkerInstanceLock(
                supportDirectory: configuration.supportDirectory,
                actorID: configuration.actorID,
                threadID: configuration.threadID
            )
            let coreClient = RelayCoreAPIClient(
                baseURL: configuration.coreServiceURL,
                authToken: configuration.coreAuthToken,
                actorID: configuration.actorID,
                actorCredential: configuration.actorCredential
            )
            try await Self.runWorkerSessions(
                configuration: configuration,
                stateStore: stateStore,
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
        instanceLock: WorkerInstanceLock,
        coreClient: RelayCoreAPIClient
    ) async throws {
        while !Task.isCancelled {
            let codexClient = CodexAppServerClient()
            let worker = try CodexRelayWorker(
                configuration: configuration,
                coreClient: coreClient,
                codexClient: codexClient,
                stateStore: stateStore,
                instanceLock: instanceLock
            )
            let account: AccountSummary
            do {
                account = try await worker.verifyChatGPTManagedAccount()
            } catch {
                try? await Self.postReadinessFailure(
                    configuration: configuration,
                    coreClient: coreClient
                )
                await codexClient.terminate()
                throw error
            }
            Self.writeStatus(
                "CodexRelayWorker ready as @\(configuration.actorID) in \(configuration.threadID) using ChatGPT-managed Codex (plan: \(String(describing: account.planType)))."
            )

            var restartCodexSession = false
            while !Task.isCancelled {
                var delayMilliseconds = configuration.pollIntervalMilliseconds
                do {
                    _ = try await worker.pollOnce()
                } catch let error as RelayWorkerRecoveryError {
                    Self.writeError(
                        "CodexRelayWorker is restarting its bounded local Codex session: \(error.localizedDescription)"
                    )
                    restartCodexSession = true
                    break
                } catch {
                    Self.writeError(
                        "CodexRelayWorker poll failed and will retry safely: \(error.localizedDescription)"
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
        coreClient: RelayCoreAPIClient
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
