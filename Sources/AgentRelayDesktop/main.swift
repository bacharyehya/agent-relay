import AppKit
import Foundation
import SwiftUI
import MacAppSupport

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
    private struct Child {
        let process: Process
        let logHandle: FileHandle?
    }

    private var children: [Child] = []
    private var ownsCoreService = false

    func start() {
        if !coreIsHealthy() {
            guard let core = startHelper(named: "CoreService", environment: [:]) else {
                return
            }
            children.append(core)
            ownsCoreService = true
            guard waitForCore() else {
                return
            }
        }

        let supportDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AgentRelay", isDirectory: true)
        let chatWorkspace = supportDirectory.appendingPathComponent("ChatWorkspace", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: chatWorkspace,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        for actorID in ["codex-main", "codex-research"] {
            let workerEnvironment = [
                "AGENT_RELAY_ACTOR_ID": actorID,
                "AGENT_RELAY_THREAD_ID": "thread-general",
                "AGENT_RELAY_POLL_INTERVAL_MS": "1500",
                "AGENT_RELAY_CODEX_CWD": chatWorkspace.path(percentEncoded: false),
            ]
            if let worker = startHelper(
                named: "CodexRelayWorker",
                environment: workerEnvironment,
                logName: actorID
            ) {
                children.append(worker)
            }
        }
    }

    func stop() {
        for child in children.reversed() where child.process.isRunning {
            child.process.terminate()
        }
        for child in children.reversed() {
            child.process.waitUntilExit()
            try? child.logHandle?.close()
        }
        children.removeAll()
        ownsCoreService = false
    }

    private func startHelper(
        named name: String,
        environment additions: [String: String],
        logName: String? = nil
    ) -> Child? {
        guard let executableURL = helperURL(named: name) else {
            NSLog("Agent Relay could not find its %@ helper.", name)
            return nil
        }

        let process = Process()
        process.executableURL = executableURL
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "OPENAI_API_KEY")
        environment.removeValue(forKey: "CODEX_API_KEY")
        for (key, value) in additions {
            environment[key] = value
        }
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        let logHandle = makeLogHandle(name: logName ?? name)
        process.standardOutput = logHandle ?? FileHandle.nullDevice
        process.standardError = logHandle ?? FileHandle.nullDevice

        do {
            try process.run()
            return Child(process: process, logHandle: logHandle)
        } catch {
            NSLog("Agent Relay could not start %@: %@", name, error.localizedDescription)
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
        _ = try? handle.seekToEnd()
        return handle
    }

    private func waitForCore() -> Bool {
        for _ in 0..<80 {
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
