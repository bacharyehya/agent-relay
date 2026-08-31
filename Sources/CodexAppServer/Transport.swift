import Foundation

public protocol CodexAppServerTransport: Sendable {
    func start() async throws
    func send(_ message: JSONValue) async throws
    func messages() async -> AsyncThrowingStream<JSONValue, any Error>
    func terminate() async
}

public enum CodexProcessTransportError: Error, Equatable, Sendable {
    case alreadyStarted
    case notStarted
    case launchFailed(String)
    case invalidMessage(String)
    case processExited(status: Int32, standardError: String)
}

extension CodexProcessTransportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .alreadyStarted:
            "The Codex app-server process is already running."
        case .notStarted:
            "The Codex app-server process has not been started."
        case let .launchFailed(message):
            "Unable to launch Codex app-server: \(message)"
        case let .invalidMessage(message):
            "Codex app-server emitted invalid JSONL: \(message)"
        case let .processExited(status, standardError):
            "Codex app-server exited with status \(status): \(standardError)"
        }
    }
}

/// A local stdio transport for the installed `codex app-server` executable.
///
/// The child inherits only the small process environment needed to find the
/// installed Codex executable and the user's existing Codex home/login. API
/// keys, custom provider URLs, cloud credentials, and proxy credentials are
/// deliberately not forwarded. The client independently verifies that
/// `account/read` reports ChatGPT-managed authentication before it starts or
/// resumes any thread.
public actor CodexProcessTransport: CodexAppServerTransport {
    private let executableURL: URL
    private let arguments: [String]
    private let baseEnvironment: [String: String]

    private let messageStream: AsyncThrowingStream<JSONValue, any Error>
    private let messageContinuation: AsyncThrowingStream<JSONValue, any Error>.Continuation

    private var process: Process?
    private var standardInput: FileHandle?
    private var standardOutput: FileHandle?
    private var standardError: FileHandle?
    private var outputBuffer = Data()
    private var errorBuffer = Data()
    private var intentionallyTerminated = false

    public init(
        executableURL: URL? = nil,
        arguments: [String]? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        if let executableURL {
            self.executableURL = executableURL
            self.arguments = arguments ?? ["app-server", "--listen", "stdio://"]
        } else if let installedCodexURL = Self.resolveInstalledCodexURL() {
            self.executableURL = installedCodexURL
            self.arguments = arguments ?? ["app-server", "--listen", "stdio://"]
        } else {
            self.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            self.arguments = arguments ?? ["codex", "app-server", "--listen", "stdio://"]
        }
        self.baseEnvironment = environment

        let pair = AsyncThrowingStream<JSONValue, any Error>.makeStream()
        self.messageStream = pair.stream
        self.messageContinuation = pair.continuation
    }

    public func messages() -> AsyncThrowingStream<JSONValue, any Error> {
        messageStream
    }

    public func start() throws {
        guard process == nil else {
            throw CodexProcessTransportError.alreadyStarted
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        process.environment = Self.sanitizedEnvironment(baseEnvironment)

        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading

        outputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await self?.consumeStandardOutput(data)
            }
        }
        errorHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await self?.consumeStandardError(data)
            }
        }
        process.terminationHandler = { [weak self] process in
            Task {
                await self?.processDidExit(status: process.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            outputHandle.readabilityHandler = nil
            errorHandle.readabilityHandler = nil
            throw CodexProcessTransportError.launchFailed(error.localizedDescription)
        }

        self.process = process
        self.standardInput = inputPipe.fileHandleForWriting
        self.standardOutput = outputHandle
        self.standardError = errorHandle
    }

    public func send(_ message: JSONValue) throws {
        guard let standardInput else {
            throw CodexProcessTransportError.notStarted
        }

        var data = try JSONEncoder().encode(message)
        data.append(0x0A)
        try standardInput.write(contentsOf: data)
    }

    public func terminate() {
        intentionallyTerminated = true
        standardOutput?.readabilityHandler = nil
        standardError?.readabilityHandler = nil
        try? standardInput?.close()

        if let process, process.isRunning {
            process.terminate()
        }

        standardInput = nil
        standardOutput = nil
        standardError = nil
        process = nil
        messageContinuation.finish()
    }

    private func consumeStandardOutput(_ data: Data) {
        guard !data.isEmpty else { return }
        outputBuffer.append(data)

        while let newlineIndex = outputBuffer.firstIndex(of: 0x0A) {
            var line = outputBuffer[..<newlineIndex]
            outputBuffer.removeSubrange(...newlineIndex)

            if line.last == 0x0D {
                line = line.dropLast()
            }
            guard !line.isEmpty else { continue }

            do {
                let value = try JSONDecoder().decode(JSONValue.self, from: Data(line))
                messageContinuation.yield(value)
            } catch {
                messageContinuation.finish(
                    throwing: CodexProcessTransportError.invalidMessage(error.localizedDescription)
                )
                if let process, process.isRunning {
                    process.terminate()
                }
            }
        }
    }

    private func consumeStandardError(_ data: Data) {
        guard !data.isEmpty else { return }
        // Keep enough diagnostic context to explain a failed launch without
        // retaining an unbounded process log in memory.
        let maximumBytes = 64 * 1024
        errorBuffer.append(data)
        if errorBuffer.count > maximumBytes {
            errorBuffer.removeFirst(errorBuffer.count - maximumBytes)
        }
    }

    private func processDidExit(status: Int32) {
        standardOutput?.readabilityHandler = nil
        standardError?.readabilityHandler = nil
        standardInput = nil
        standardOutput = nil
        standardError = nil
        process = nil

        guard !intentionallyTerminated else {
            messageContinuation.finish()
            return
        }

        let errorText = String(decoding: errorBuffer, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        messageContinuation.finish(
            throwing: CodexProcessTransportError.processExited(
                status: status,
                standardError: errorText
            )
        )
    }

    static func sanitizedEnvironment(_ environment: [String: String]) -> [String: String] {
        let allowedKeys: Set<String> = [
            "CODEX_HOME",
            "HOME",
            "LANG",
            "LC_ALL",
            "LC_CTYPE",
            "LOGNAME",
            "PATH",
            "SHELL",
            "TERM",
            "TMPDIR",
            "USER",
        ]
        return environment.filter { key, _ in
            allowedKeys.contains(key) || key.hasPrefix("LC_")
        }
    }

    static func resolveInstalledCodexURL(
        candidateURLs: [URL] = [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/codex", isDirectory: false),
        ],
        fileManager: FileManager = .default
    ) -> URL? {
        candidateURLs.first {
            fileManager.isExecutableFile(atPath: $0.path(percentEncoded: false))
        }
    }
}
