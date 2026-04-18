import Foundation
import Security

public enum AppRuntimeConfiguration {
    public static let supportDirectoryName = "AgentRelay"
    public static let databaseFileName = "agent-relay.sqlite"
    public static let authTokenFileName = "auth-token"
    public static let defaultCoreHost = "127.0.0.1"
    public static let defaultCorePort = 8080

    public static func supportDirectory(
        environment: [String: String],
        overrideSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        if let overrideSupportDirectory {
            try createDirectoryIfNeeded(at: overrideSupportDirectory, fileManager: fileManager)
            return overrideSupportDirectory
        }

        if let customRoot = environment["AGENT_RELAY_SUPPORT_DIR"], !customRoot.isEmpty {
            let url = URL(fileURLWithPath: customRoot, isDirectory: true)
            try createDirectoryIfNeeded(at: url, fileManager: fileManager)
            return url
        }

        let baseDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = baseDirectory.appendingPathComponent(supportDirectoryName, isDirectory: true)
        try createDirectoryIfNeeded(at: url, fileManager: fileManager)
        return url
    }

    public static func databaseURL(
        environment: [String: String],
        supportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        if let rawPath = environment["AGENT_RELAY_DB_PATH"], !rawPath.isEmpty {
            return URL(fileURLWithPath: rawPath, isDirectory: false)
        }

        return try self.supportDirectory(
            environment: environment,
            overrideSupportDirectory: supportDirectory,
            fileManager: fileManager
        ).appendingPathComponent(databaseFileName, isDirectory: false)
    }

    public static func coreServiceURL(environment: [String: String]) -> URL {
        if let rawURL = environment["AGENT_RELAY_CORE_URL"], let url = URL(string: rawURL) {
            return url
        }

        let host = environment["AGENT_RELAY_CORE_HOST"] ?? defaultCoreHost
        let port = Int(environment["AGENT_RELAY_CORE_PORT"] ?? "") ?? defaultCorePort
        return URL(string: "http://\(host):\(port)")!
    }

    public static func loadOrCreateAuthToken(
        environment: [String: String],
        supportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> String {
        if let override = environment["AGENT_RELAY_AUTH_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty
        {
            return override
        }

        let tokenURL = try self.supportDirectory(
            environment: environment,
            overrideSupportDirectory: supportDirectory,
            fileManager: fileManager
        ).appendingPathComponent(authTokenFileName, isDirectory: false)

        if fileManager.fileExists(atPath: tokenURL.path()) {
            let existing = try String(contentsOf: tokenURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !existing.isEmpty {
                return existing
            }
        }

        let token = try generateAuthToken()
        try token.write(to: tokenURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path())
        return token
    }

    private static func createDirectoryIfNeeded(at url: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private static func generateAuthToken(byteCount: Int = 32) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw NSError(
                domain: "AppRuntimeConfiguration",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Unable to generate an auth token"]
            )
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
