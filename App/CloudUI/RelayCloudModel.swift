import AppCore
import Foundation
import Observation
import RelayCloudClient

@MainActor
@Observable
public final class RelayCloudModel {
    private enum AgentHostEnrollmentError: LocalizedError {
        case unavailable
        case humanInvitation
        case missingRoom

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "Install and open Agent Relay Host to connect a Codex agent on this Mac."
            case .humanInvitation:
                "That code is for a human device. Create an Agent invitation instead."
            case .missingRoom:
                "The invitation did not include a room for the agent to watch."
            }
        }
    }

    public enum Phase: Equatable {
        case checking
        case signedOut
        case signedIn
    }

    public enum ConnectionState: Equatable {
        case connecting
        case connected
        case offline
    }

    public var phase: Phase = .checking
    public var connectionState: ConnectionState = .connecting
    public var storedSession: RelayStoredSession?
    public var workspace: RelayWorkspace?
    public var currentActor: RelayCloudActor?
    public var actors: [RelayCloudActor] = []
    public var rooms: [RelayCloudRoom] = []
    public var messagesByRoom: [String: [RelayCloudMessage]] = [:]
    public var readReceipts: [String: Int] = [:]
    public var presence: [RelayPresence] = []
    public var selectedRoomID: String?
    public var errorMessage: String?
    public var isWorking = false
    public var searchResults: [RelayCloudMessage] = []
    public var activeInvitation: RelayInvitation?
    public var localAgentSetupMessage: String?
    public var localAgentsInstalled = false
    public var localAgentIDs: [String] = []
    public var agentHostSetupMessage: String?
    public let allowsLocalAgentHosting: Bool

    private let store: RelaySessionStore
    private var api: RelayCloudAPI?
    private var cursor = 0
    private var syncTask: Task<Void, Never>?

    public init(
        store: RelaySessionStore = .live,
        allowsLocalAgentHosting: Bool = false
    ) {
        self.store = store
        self.allowsLocalAgentHosting = allowsLocalAgentHosting
    }

    public func restore() async {
        guard phase == .checking else { return }
        do {
            guard let saved = try store.load() else {
                phase = .signedOut
                connectionState = .offline
                return
            }
            let api = try RelayCloudAPI(baseURL: saved.session.serverURL, token: saved.token)
            let identity = try await api.me()
            let refreshedSession = RelayStoredSession(
                serverURL: saved.session.serverURL,
                workspace: identity.workspace,
                actor: identity.actor,
                deviceID: identity.device.id,
                deviceName: identity.device.name ?? identity.device.deviceName ?? saved.session.deviceName
            )
            self.api = api
            storedSession = refreshedSession
            workspace = identity.workspace
            currentActor = identity.actor
            phase = .signedIn
            connectionState = .connected
            try? store.save(session: refreshedSession, token: saved.token)
            await syncOnce()
            refreshLocalAgentInstallationState()
            startSyncLoop()
        } catch {
            phase = .signedOut
            connectionState = .offline
            errorMessage = error.localizedDescription
        }
    }

    public func join(serverURL: String, code: String, deviceName: String) async {
        await performEnrollment(serverURL: serverURL, deviceName: deviceName) { api in
            try await api.enroll(code: code, deviceName: deviceName)
        }
    }

    public func joinAgentHost(serverURL: String, code: String, deviceName: String) async {
        isWorking = true
        connectionState = .connecting
        defer { isWorking = false }
        do {
            guard allowsLocalAgentHosting else {
                throw AgentHostEnrollmentError.unavailable
            }
            guard let url = Self.normalizedServerURL(serverURL) else {
                throw RelayCloudError.invalidServerURL
            }
            if let existing = try RelayCloudAgentInstaller.load(), existing.serverURL != url {
                throw RelayCloudAgentInstallerError.differentRelayAlreadyConfigured
            }
            let unsignedAPI = try RelayCloudAPI(baseURL: url)
            _ = try await unsignedAPI.health()
            let envelope = try await unsignedAPI.enroll(code: code, deviceName: deviceName)
            guard envelope.actor.type == .agent else {
                throw AgentHostEnrollmentError.humanInvitation
            }
            guard let room = envelope.room else {
                throw AgentHostEnrollmentError.missingRoom
            }
            _ = try RelayCloudAgentInstaller.install(
                serverURL: url,
                roomID: room.id,
                actorID: envelope.actor.id,
                token: envelope.token
            )
            UserDefaults.standard.set(url.absoluteString, forKey: "AgentRelay.Cloud.LastServerURL")
            refreshLocalAgentInstallationState()
            agentHostSetupMessage = "@\(envelope.actor.id) is connected on this Mac. The Host will keep it running."
            connectionState = .connected
            errorMessage = nil
        } catch {
            connectionState = .offline
            agentHostSetupMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    public func createOwner(
        serverURL: String,
        bootstrapKey: String,
        workspaceName: String,
        displayName: String,
        deviceName: String
    ) async {
        await performEnrollment(serverURL: serverURL, deviceName: deviceName) { api in
            try await api.bootstrap(
                key: bootstrapKey,
                workspaceName: workspaceName,
                actorID: "bash",
                displayName: displayName,
                deviceName: deviceName
            )
        }
    }

    public func syncOnce() async {
        guard let api, phase == .signedIn else { return }
        do {
            var hasMore = true
            while hasMore {
                let snapshot = try await api.sync(after: cursor)
                merge(snapshot)
                cursor = max(cursor, snapshot.nextCursor)
                hasMore = snapshot.hasMore
            }
            if let storedSession {
                _ = try? await api.updatePresence(state: "online", deviceName: storedSession.deviceName)
            }
            connectionState = .connected
            errorMessage = nil
        } catch {
            connectionState = .offline
            errorMessage = error.localizedDescription
        }
    }

    public func startSyncLoop() {
        guard syncTask == nil else { return }
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncOnce()
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    break
                }
            }
        }
    }

    public func stopSyncLoop() {
        syncTask?.cancel()
        syncTask = nil
    }

    public func send(
        body: String,
        roomID: String,
        replyToMessageID: String? = nil
    ) async -> Bool {
        guard let api else { return false }
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return false }
        let mentions = actors.compactMap { actor in
            trimmedBody.range(of: "@\(actor.id)", options: [.caseInsensitive, .diacriticInsensitive]) == nil
                ? nil
                : actor.id
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let message = try await api.postMessage(
                roomID: roomID,
                message: RelayPostMessage(
                    body: trimmedBody,
                    replyToMessageID: replyToMessageID,
                    mentionedActorIDs: mentions
                ),
                idempotencyKey: UUID().uuidString.lowercased()
            )
            merge(messages: [message])
            cursor = max(cursor, message.sequence)
            connectionState = .connected
            errorMessage = nil
            return true
        } catch {
            connectionState = .offline
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func markSelectedRoomRead() async {
        guard let api, let roomID = selectedRoomID,
              let sequence = messagesByRoom[roomID]?.last?.sequence
        else { return }
        if let receipt = try? await api.markRead(roomID: roomID, sequence: sequence) {
            readReceipts[roomID] = max(readReceipts[roomID] ?? 0, receipt.lastReadSequence)
        }
    }

    public func createRoom(name: String, topic: String) async -> Bool {
        guard let api else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            let room = try await api.createRoom(name: name, topic: topic)
            rooms.removeAll { $0.id == room.id }
            rooms.insert(room, at: 0)
            selectedRoomID = room.id
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func createAgentInvitation(actorID: String, displayName: String) async {
        guard let api else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            activeInvitation = try await api.createAgentInvitation(actorID: actorID, displayName: displayName)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func createHumanDeviceInvitation() async {
        guard let api else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            activeInvitation = try await api.createHumanDeviceInvitation()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func installLocalMacAgents() async {
        guard allowsLocalAgentHosting else {
            errorMessage = AgentHostEnrollmentError.unavailable.localizedDescription
            return
        }
        guard let api,
              let storedSession,
              let roomID = rooms.first(where: { $0.name == "general" })?.id
        else {
            localAgentSetupMessage = "Open General and wait for Relay to finish syncing, then try again."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let unsignedAPI = try RelayCloudAPI(baseURL: storedSession.serverURL)
            let agents = [
                (RelayAgentProfile.main.id, RelayAgentProfile.main.displayName),
                (RelayAgentProfile.research.id, RelayAgentProfile.research.displayName),
            ]
            for (actorID, displayName) in agents {
                let invitation = try await api.createAgentInvitation(
                    actorID: actorID,
                    displayName: displayName
                )
                let enrollment = try await unsignedAPI.enroll(
                    code: invitation.code,
                    deviceName: "\(ProcessInfo.processInfo.hostName) · \(displayName)"
                )
                _ = try RelayCloudAgentInstaller.install(
                    serverURL: storedSession.serverURL,
                    roomID: roomID,
                    actorID: actorID,
                    token: enrollment.token
                )
            }
            localAgentsInstalled = true
            localAgentSetupMessage = "Main and Research are connected on this Mac."
            errorMessage = nil
            await syncOnce()
        } catch {
            localAgentSetupMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    public func search(_ query: String) async {
        guard let api else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        do {
            searchResults = try await api.search(trimmed)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func signOut() {
        stopSyncLoop()
        try? store.clear()
        api = nil
        storedSession = nil
        workspace = nil
        currentActor = nil
        actors = []
        rooms = []
        messagesByRoom = [:]
        readReceipts = [:]
        presence = []
        selectedRoomID = nil
        cursor = 0
        phase = .signedOut
        connectionState = .offline
        localAgentSetupMessage = nil
        localAgentsInstalled = false
    }

    public func messages(in roomID: String) -> [RelayCloudMessage] {
        messagesByRoom[roomID] ?? []
    }

    public func actor(id: String) -> RelayCloudActor? {
        actors.first { $0.id == id }
    }

    public func unreadCount(roomID: String) -> Int {
        let latest = messagesByRoom[roomID]?.last?.sequence ?? rooms.first { $0.id == roomID }?.latestSequence ?? 0
        return max(0, latest - (readReceipts[roomID] ?? 0))
    }

    public func isOnline(actorID: String) -> Bool {
        presence.contains { $0.actorID == actorID && $0.state == "online" }
    }

    private func performEnrollment(
        serverURL: String,
        deviceName: String,
        operation: (RelayCloudAPI) async throws -> RelayEnrollmentEnvelope
    ) async {
        isWorking = true
        connectionState = .connecting
        defer { isWorking = false }
        do {
            guard let url = Self.normalizedServerURL(serverURL) else {
                throw RelayCloudError.invalidServerURL
            }
            let unsignedAPI = try RelayCloudAPI(baseURL: url)
            _ = try await unsignedAPI.health()
            let envelope = try await operation(unsignedAPI)
            let authenticatedAPI = try RelayCloudAPI(baseURL: url, token: envelope.token)
            let resolvedDeviceName = envelope.device.name ?? envelope.device.deviceName ?? deviceName
            let saved = RelayStoredSession(
                serverURL: url,
                workspace: envelope.workspace,
                actor: envelope.actor,
                deviceID: envelope.device.id,
                deviceName: resolvedDeviceName
            )
            try store.save(session: saved, token: envelope.token)
            UserDefaults.standard.set(url.absoluteString, forKey: "AgentRelay.Cloud.LastServerURL")
            api = authenticatedAPI
            storedSession = saved
            workspace = envelope.workspace
            currentActor = envelope.actor
            selectedRoomID = envelope.room?.id
            phase = .signedIn
            connectionState = .connected
            errorMessage = nil
            await syncOnce()
            startSyncLoop()
        } catch {
            phase = .signedOut
            connectionState = .offline
            errorMessage = error.localizedDescription
        }
    }

    private func merge(_ snapshot: RelaySyncSnapshot) {
        workspace = snapshot.workspace
        actors = snapshot.actors
        rooms = snapshot.rooms.filter { !$0.isArchived }
        readReceipts = Dictionary(uniqueKeysWithValues: snapshot.readReceipts.map { ($0.roomID, $0.lastReadSequence) })
        presence = snapshot.presence
        merge(messages: snapshot.messages)
        if selectedRoomID == nil || !rooms.contains(where: { $0.id == selectedRoomID }) {
            selectedRoomID = rooms.first?.id
        }
    }

    private func merge(messages: [RelayCloudMessage]) {
        for message in messages {
            var roomMessages = messagesByRoom[message.roomID] ?? []
            roomMessages.removeAll { $0.id == message.id }
            roomMessages.append(message)
            roomMessages.sort { lhs, rhs in
                lhs.sequence == rhs.sequence ? lhs.id < rhs.id : lhs.sequence < rhs.sequence
            }
            messagesByRoom[message.roomID] = roomMessages
        }
    }

    private static func normalizedServerURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: candidate), components.host != nil else { return nil }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return components.url
    }

    private func refreshLocalAgentInstallationState() {
        let expected = Set([RelayAgentProfile.main.id, RelayAgentProfile.research.id])
        let configured = (try? RelayCloudAgentInstaller.load())?.actorIDs ?? []
        localAgentIDs = configured
        localAgentsInstalled = expected.isSubset(of: Set(configured))
        if localAgentsInstalled {
            localAgentSetupMessage = "Main and Research are connected on this Mac."
        }
    }
}
