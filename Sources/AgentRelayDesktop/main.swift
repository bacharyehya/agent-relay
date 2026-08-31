import AppKit
import Darwin
import Foundation
import MacAppSupport
import RelayCloudClient
import RelayCloudKit
import SwiftUI

@MainActor
private final class AgentRelayAppDelegate: NSObject, NSApplicationDelegate {
    private let runtime = LocalRuntime()

    func applicationWillFinishLaunching(_ notification: Notification) {
        runtime.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime.stop()
    }
}

@MainActor
private final class LocalRuntime {
    private struct HelperSpec {
        let key: String
        let executableName: String
        let environment: [String: String]
        let logName: String
    }

    private struct Child {
        let process: Process
        let logHandle: FileHandle?
    }

    private let coreSpec = HelperSpec(
        key: "core",
        executableName: "CoreService",
        environment: [:],
        logName: "CoreService"
    )
    private var workerSpecs: [HelperSpec] {
        let supportDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AgentRelay", isDirectory: true)
        let chatWorkspace = supportDirectory.appendingPathComponent("ChatWorkspace", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: chatWorkspace,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let localWorkersEnabled = !["0", "false", "no"].contains(
            ProcessInfo.processInfo.environment["AGENT_RELAY_ENABLE_LOCAL_AGENTS"]?.lowercased() ?? "true"
        )
        var cloudKitActorIDs = Set(
            localWorkersEnabled ? ["codex-main", "codex-research"] : []
        )
        if let configuration = try? RelayCloudKitAgentInstaller.load() {
            cloudKitActorIDs.formUnion(configuration.actorIDs)
        }
        var specs = cloudKitActorIDs.sorted().map { actorID in
            HelperSpec(
                key: "cloudkit-\(actorID)",
                executableName: "CodexRelayWorker",
                environment: [
                    "AGENT_RELAY_ACTOR_ID": actorID,
                    "AGENT_RELAY_TRANSPORT": "cloudkit",
                    "AGENT_RELAY_THREAD_ID": "thread-general",
                    "AGENT_RELAY_POLL_INTERVAL_MS": "1500",
                    "AGENT_RELAY_CODEX_CWD": chatWorkspace.path(percentEncoded: false),
                ],
                logName: "cloudkit-\(actorID)"
            )
        }

        let legacyCloudEnabled = ["1", "true", "yes"].contains(
            ProcessInfo.processInfo.environment["AGENT_RELAY_ENABLE_LEGACY_CLOUD"]?.lowercased() ?? "false"
        )
        if legacyCloudEnabled, let configuration = try? RelayCloudAgentInstaller.load() {
            for actorID in configuration.actorIDs {
                guard let tokenURL = try? RelayCloudAgentInstaller.tokenFileURL(actorID: actorID) else {
                    continue
                }
                specs.append(
                    HelperSpec(
                        key: "cloud-\(actorID)",
                        executableName: "CodexRelayWorker",
                        environment: [
                            "AGENT_RELAY_ACTOR_ID": actorID,
                            "AGENT_RELAY_TRANSPORT": "cloud",
                            "AGENT_RELAY_THREAD_ID": configuration.roomID,
                            "AGENT_RELAY_POLL_INTERVAL_MS": "15000",
                            "AGENT_RELAY_CODEX_CWD": chatWorkspace.path(percentEncoded: false),
                            "AGENT_RELAY_CLOUD_URL": configuration.serverURL.absoluteString,
                            "AGENT_RELAY_CLOUD_TOKEN_FILE": tokenURL.path(percentEncoded: false),
                            "AGENT_RELAY_CLOUD_DEVICE_NAME": ProcessInfo.processInfo.hostName,
                        ],
                        logName: "cloud-\(actorID)"
                    )
                )
            }
        }
        return specs
    }

    private var children: [String: Child] = [:]
    private var ownsCoreService = false
    private var isStopping = false
    private var supervisionTask: Task<Void, Never>?

    func start() {
        guard supervisionTask == nil else { return }
        isStopping = false
        if ensureCoreIsRunning() {
            ensureWorkersAreRunning()
        }

        supervisionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(3))
                } catch {
                    break
                }
                self?.supervise()
            }
        }
    }

    func stop() {
        isStopping = true
        supervisionTask?.cancel()
        supervisionTask = nil

        for (key, child) in children where key != coreSpec.key || ownsCoreService {
            if child.process.isRunning {
                child.process.terminate()
            }
        }

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline,
              children.values.contains(where: { $0.process.isRunning })
        {
            Thread.sleep(forTimeInterval: 0.05)
        }

        for (key, child) in children where key != coreSpec.key || ownsCoreService {
            if child.process.isRunning {
                Darwin.kill(child.process.processIdentifier, SIGKILL)
            }
            child.process.waitUntilExit()
            try? child.logHandle?.close()
        }
        children.removeAll()
        ownsCoreService = false
    }

    private func supervise() {
        guard !isStopping else { return }
        reapExitedHelpers()
        if ensureCoreIsRunning() {
            ensureWorkersAreRunning()
        }
    }

    private func reapExitedHelpers() {
        let exitedKeys = children.compactMap { key, child in
            child.process.isRunning ? nil : key
        }
        for key in exitedKeys {
            guard let child = children.removeValue(forKey: key) else { continue }
            child.process.waitUntilExit()
            try? child.logHandle?.close()
        }
    }

    @discardableResult
    private func ensureCoreIsRunning() -> Bool {
        if coreIsHealthy() {
            return true
        }

        if let child = children[coreSpec.key], child.process.isRunning {
            if waitForCore(attempts: 10) {
                return true
            }
            child.process.terminate()
            return false
        }

        guard let core = startHelper(coreSpec) else {
            return false
        }
        children[coreSpec.key] = core
        ownsCoreService = true
        return waitForCore()
    }

    private func ensureWorkersAreRunning() {
        for spec in workerSpecs where children[spec.key]?.process.isRunning != true {
            if let worker = startHelper(spec) {
                children[spec.key] = worker
            }
        }
    }

    private func startHelper(_ spec: HelperSpec) -> Child? {
        guard let executableURL = helperURL(named: spec.executableName) else {
            NSLog("Agent Relay could not find its %@ helper.", spec.executableName)
            return nil
        }

        let process = Process()
        process.executableURL = executableURL
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "OPENAI_API_KEY")
        environment.removeValue(forKey: "CODEX_API_KEY")
        for (key, value) in spec.environment {
            environment[key] = value
        }
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        let logHandle = makeLogHandle(name: spec.logName)
        process.standardOutput = logHandle ?? FileHandle.nullDevice
        process.standardError = logHandle ?? FileHandle.nullDevice

        do {
            try process.run()
            return Child(process: process, logHandle: logHandle)
        } catch {
            NSLog(
                "Agent Relay could not start %@: %@",
                spec.executableName,
                error.localizedDescription
            )
            try? logHandle?.close()
            return nil
        }
    }

    private func helperURL(named name: String) -> URL? {
        var candidates: [URL] = []
        if let executablePath = CommandLine.arguments.first, executablePath.hasPrefix("/") {
            let macOSDirectory = URL(fileURLWithPath: executablePath, isDirectory: false)
                .standardizedFileURL
                .deletingLastPathComponent()
            candidates.append(
                macOSDirectory
                    .deletingLastPathComponent()
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent(name, isDirectory: false)
            )
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent(name, isDirectory: false))
        }
        if let executable = Bundle.main.executableURL {
            let macOSDirectory = executable.deletingLastPathComponent()
            candidates.append(macOSDirectory.appendingPathComponent(name))
            candidates.append(
                macOSDirectory
                    .deletingLastPathComponent()
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent(name, isDirectory: false)
            )
        }
        if let helper = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false))
        }) {
            return helper
        }
        NSLog(
            "Agent Relay helper %@ was not found in: %@",
            name,
            candidates.map { $0.path(percentEncoded: false) }.joined(separator: ", ")
        )
        return nil
    }

    private func makeLogHandle(name: String) -> FileHandle? {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AgentRelay", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = directory.appendingPathComponent("\(name).log", isDirectory: false)
        let logPath = url.path(percentEncoded: false)
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            return nil
        }

        let byteCount = (try? handle.seekToEnd()) ?? 0
        if byteCount > 2_000_000 {
            try? handle.truncate(atOffset: 0)
            try? handle.seek(toOffset: 0)
        }
        return handle
    }

    private func waitForCore(attempts: Int = 80) -> Bool {
        for _ in 0..<attempts {
            if coreIsHealthy() {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    private func coreIsHealthy() -> Bool {
        guard let url = URL(string: "http://127.0.0.1:8080/health"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else {
            return false
        }
        return object["status"] == "ok"
    }
}

@main
struct AgentRelayDesktopApp: App {
    @NSApplicationDelegateAdaptor(AgentRelayAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AgentRelayRootView()
        }
        .defaultSize(width: 1180, height: 760)
    }
}
