import Foundation
import Security

public enum RelaySessionStoreError: Error, LocalizedError, Sendable {
    case encodingFailed
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Agent Relay could not save this device session."
        case let .keychain(status):
            return "Agent Relay could not access its device credential (\(status))."
        }
    }
}

public struct RelaySessionStore: Sendable {
    public static let live = RelaySessionStore()
    public static let sessionDefaultsKey = "AgentRelay.Cloud.Session.v1"
    private static let keychainService = "io.agentrelay.cloud.session"

    public init() {}

    public func load() throws -> (session: RelayStoredSession, token: String)? {
        guard let data = UserDefaults.standard.data(forKey: Self.sessionDefaultsKey),
              let session = try? JSONDecoder().decode(RelayStoredSession.self, from: data)
        else {
            return nil
        }
        guard let token = try readToken(account: session.deviceID) else {
            return nil
        }
        return (session, token)
    }

    public func save(session: RelayStoredSession, token: String) throws {
        guard let data = try? JSONEncoder().encode(session) else {
            throw RelaySessionStoreError.encodingFailed
        }
        try writeToken(token, account: session.deviceID)
        UserDefaults.standard.set(data, forKey: Self.sessionDefaultsKey)
    }

    public func clear() throws {
        if let data = UserDefaults.standard.data(forKey: Self.sessionDefaultsKey),
           let session = try? JSONDecoder().decode(RelayStoredSession.self, from: data)
        {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.keychainService,
                kSecAttrAccount as String: session.deviceID,
            ]
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                throw RelaySessionStoreError.keychain(status)
            }
        }
        UserDefaults.standard.removeObject(forKey: Self.sessionDefaultsKey)
    }

    private func readToken(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw RelaySessionStoreError.keychain(status) }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw RelaySessionStoreError.encodingFailed
        }
        return token
    }

    private func writeToken(_ token: String, account: String) throws {
        guard let data = token.data(using: .utf8) else { throw RelaySessionStoreError.encodingFailed }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insertion = query
            insertion[kSecValueData as String] = data
            insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let insertStatus = SecItemAdd(insertion as CFDictionary, nil)
            guard insertStatus == errSecSuccess else { throw RelaySessionStoreError.keychain(insertStatus) }
        } else if updateStatus != errSecSuccess {
            throw RelaySessionStoreError.keychain(updateStatus)
        }
    }
}
