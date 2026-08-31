import AppCore
import Foundation
import Observation
import RelayCloudClient
import RelayCloudKit

@MainActor
@Observable
public final class RelayCloudModel {
    static let localOutboxScanIntervalSeconds = 1
    static let usesPushDrivenCloudSync = true

    private enum AgentHostError: LocalizedError {
        case unavailable
        case missingRoom
        case cachedReadOnly

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "Install and open Agent Relay Host to connect a Codex agent on this Mac."
            case .missingRoom:
                "General has not finished syncing yet. Try again in a moment."
            case .cachedReadOnly:
                "Cached history is read-only until Agent Relay reconnects to iCloud."
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
    public var localAgentSetupMessage: String?
    public var localAgentsInstalled = false
    public var localAgentIDs: [String] = []
    public var canWrite = false
    public let allowsLocalAgentHosting: Bool
    public let deviceName: String

    private var database: RelayCloudKitDatabase?
    private var snapshotTask: Task<Void, Never>?
    private var outboxTask: Task<Void, Never>?

    public init(allowsLocalAgentHosting: Bool = false) {
        self.allowsLocalAgentHosting = allowsLocalAgentHosting
        self.deviceName = ProcessInfo.processInfo.hostName
    }

    public func restore() async {
        guard phase == .checking else { return }
        connectionState = .connecting
        do {
            let database = try RelayCloudKitDatabase()
            self.database = database
            observe(database)
            try await database.start(deviceName: deviceName)
            await importLegacyLocalMessagesIfNeeded(into: database)
            merge(await database.snapshot())
            phase = .signedIn
            connectionState = .connected
            canWrite = true
            errorMessage = nil
            refreshLocalAgentInstallationState()
            startLocalOutboxMonitor()
        } catch {
            if let database = self.database,
               await database.hasCachedWorkspace(),
               RelayCloudKitFailurePolicy.allowsCachedMode(for: error)
            {
                merge(await database.snapshot())
                phase = .signedIn
                connectionState = .offline
                canWrite = false
                errorMessage = error.localizedDescription
                refreshLocalAgentInstallationState()
            } else {
                stopBackgroundWork()
                self.database = nil
                phase = .signedOut
                connectionState = .offline
                canWrite = false
                errorMessage = error.localizedDescription
            }
        }
    }

    public func connectToICloud() async {
        phase = .checking
        errorMessage = nil
        await restore()
    }

    public func syncOnce() async {
        guard let database, phase == .signedIn else { return }
        connectionState = .connecting
        do {
            try await database.synchronize()
            merge(await database.snapshot())
            connectionState = .connected
            canWrite = true
            errorMessage = nil
            startLocalOutboxMonitor()
        } catch {
            if RelayCloudKitFailurePolicy.allowsCachedMode(for: error) {
                connectionState = .offline
                errorMessage = error.localizedDescription
            } else {
                stopBackgroundWork()
                self.database = nil
                phase = .signedOut
                connectionState = .offline
                canWrite = false
                errorMessage = error.localizedDescription
            }
        }
    }

    public func send(
        body: String,
        roomID: String,
        replyToMessageID: String? = nil
    ) async -> Bool {
        guard let database, canWrite else {
            errorMessage = AgentHostError.cachedReadOnly.localizedDescription
            return false
        }
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return false }
        let mentions = actors.compactMap { actor in
            trimmedBody.range(
                of: "@\(actor.id)",
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == nil ? nil : actor.id
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let message = try await database.postMessage(
                roomID: roomID,
                actorID: currentActor?.id ?? RelayCloudKitDatabase.humanActorID,
                body: trimmedBody,
                replyToMessageID: replyToMessageID,
                mentionedActorIDs: mentions
            )
            merge(messages: [message])
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
        guard canWrite,
              let database,
              let roomID = selectedRoomID,
              let sequence = messagesByRoom[roomID]?.last?.sequence
        else { return }
        do {
            try await database.markRead(
                roomID: roomID,
                actorID: currentActor?.id ?? RelayCloudKitDatabase.humanActorID,
                sequence: sequence
            )
            readReceipts[roomID] = max(readReceipts[roomID] ?? 0, sequence)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func createRoom(name: String, topic: String) async -> Bool {
        guard let database, canWrite else {
            errorMessage = AgentHostError.cachedReadOnly.localizedDescription
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let room = try await database.createRoom(name: name, topic: topic)
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

    public func addAgent(actorID: String, displayName: String) async -> Bool {
        guard let database, canWrite else {
            errorMessage = AgentHostError.cachedReadOnly.localizedDescription
            return false
        }
        let id = actorID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !name.isEmpty else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            let actor = try await database.addAgent(actorID: id, displayName: name)
            actors.removeAll { $0.id == actor.id }
            actors.append(actor)
            actors.sort { $0.id < $1.id }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func installLocalMacAgents() async {
        for profile in [RelayAgentProfile.main, RelayAgentProfile.research] {
            guard await installLocalAgent(actorID: profile.id, displayName: profile.displayName) else {
                return
            }
        }
        localAgentSetupMessage = "Main and Research are connected through this Mac."
    }

    @discardableResult
    public func installLocalAgent(actorID: String, displayName: String) async -> Bool {
        guard allowsLocalAgentHosting else {
            errorMessage = AgentHostError.unavailable.localizedDescription
            return false
        }
        guard canWrite else {
            errorMessage = AgentHostError.cachedReadOnly.localizedDescription
            return false
        }
        guard let roomID = rooms.first(where: { $0.name == "general" })?.id else {
            errorMessage = AgentHostError.missingRoom.localizedDescription
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try RelayCloudKitAgentInstaller.install(roomID: roomID, actorID: actorID)
            if let database {
                _ = try await database.addAgent(actorID: actorID, displayName: displayName)
            }
            refreshLocalAgentInstallationState()
            localAgentSetupMessage = "@\(actorID) is connected through this Mac."
            errorMessage = nil
            return true
        } catch {
            localAgentSetupMessage = nil
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        searchResults = messagesByRoom.values
            .flatMap { $0 }
            .filter {
                $0.body.localizedCaseInsensitiveContains(trimmed)
                    || $0.actorID.localizedCaseInsensitiveContains(trimmed)
            }
            .sorted { $0.sequence > $1.sequence }
        errorMessage = nil
    }

    public func messages(in roomID: String) -> [RelayCloudMessage] {
        messagesByRoom[roomID] ?? []
    }

    public func actor(id: String) -> RelayCloudActor? {
        actors.first { $0.id == id }
    }

    public func unreadCount(roomID: String) -> Int {
        if let count = rooms.first(where: { $0.id == roomID })?.unreadCount {
            return count
        }
        let receipt = readReceipts[roomID] ?? 0
        return messagesByRoom[roomID]?.filter { $0.sequence > receipt }.count ?? 0
    }

    public func isOnline(actorID: String) -> Bool {
        presence.contains {
            $0.actorID == actorID
                && $0.state == "online"
                && Date().timeIntervalSince($0.lastSeenAt) < 300
        }
    }

    private func observe(_ database: RelayCloudKitDatabase) {
        snapshotTask?.cancel()
        snapshotTask = Task { [weak self] in
            let stream = await database.snapshots()
            for await snapshot in stream {
                guard !Task.isCancelled else { break }
                self?.merge(snapshot)
            }
        }
    }

    private func startLocalOutboxMonitor() {
        guard allowsLocalAgentHosting, outboxTask == nil, let database else { return }
        outboxTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let count = try await database.drainOutbox()
                    if count > 0 {
                        self?.connectionState = .connected
                        self?.errorMessage = nil
                    }
                    try await Task.sleep(for: .seconds(Self.localOutboxScanIntervalSeconds))
                } catch is CancellationError {
                    break
                } catch {
                    self?.connectionState = .offline
                    self?.errorMessage = error.localizedDescription
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
    }

    private func stopBackgroundWork() {
        snapshotTask?.cancel()
        snapshotTask = nil
        outboxTask?.cancel()
        outboxTask = nil
    }

    private func merge(_ snapshot: RelaySyncSnapshot) {
        workspace = snapshot.workspace
        actors = snapshot.actors
        currentActor = snapshot.actors.first { $0.id == snapshot.currentActorID }
        rooms = snapshot.rooms.filter { !$0.isArchived }
        readReceipts = Dictionary(
            snapshot.readReceipts.map { ($0.roomID, $0.lastReadSequence) },
            uniquingKeysWith: max
        )
        presence = snapshot.presence
        messagesByRoom = Dictionary(grouping: snapshot.messages, by: \.roomID)
            .mapValues { messages in
                messages.sorted {
                    $0.sequence == $1.sequence ? $0.id < $1.id : $0.sequence < $1.sequence
                }
            }
        if selectedRoomID == nil || !rooms.contains(where: { $0.id == selectedRoomID }) {
            selectedRoomID = rooms.first?.id
        }
    }

    private func merge(messages: [RelayCloudMessage]) {
        for message in messages {
            var roomMessages = messagesByRoom[message.roomID] ?? []
            roomMessages.removeAll { $0.id == message.id }
            roomMessages.append(message)
            roomMessages.sort {
                $0.sequence == $1.sequence ? $0.id < $1.id : $0.sequence < $1.sequence
            }
            messagesByRoom[message.roomID] = roomMessages
        }
    }

    private func refreshLocalAgentInstallationState() {
        let configured = (try? RelayCloudKitAgentInstaller.load())?.actorIDs ?? []
        localAgentIDs = configured
        let expected = Set([RelayAgentProfile.main.id, RelayAgentProfile.research.id])
        localAgentsInstalled = expected.isSubset(of: Set(configured))
        if localAgentsInstalled {
            localAgentSetupMessage = "Main and Research are connected through this Mac."
        }
    }

    private func importLegacyLocalMessagesIfNeeded(into database: RelayCloudKitDatabase) async {
        guard allowsLocalAgentHosting,
              await database.snapshot().messages.isEmpty,
              let legacyMessages = try? await Self.fetchLegacyLocalMessages(),
              !legacyMessages.isEmpty
        else {
            return
        }
        let cloudMessages = legacyMessages.enumerated().map { index, message in
            RelayCloudMessage(
                id: message.id,
                sequence: message.sequence
                    ?? Int((message.createdAt.timeIntervalSince1970 * 1_000_000).rounded(.down)) + index,
                roomID: message.threadID,
                threadID: message.threadID,
                actorID: message.actorID,
                body: message.body,
                format: message.format,
                replyToMessageID: message.replyToMessageID,
                mentionedActorIDs: message.mentionedActorIDs,
                createdAt: message.createdAt,
                editedAt: nil
            )
        }
        _ = try? await database.importMessages(cloudMessages)
    }

    private static func fetchLegacyLocalMessages() async throws -> [Message] {
        let environment = ProcessInfo.processInfo.environment
        let token = try AppRuntimeConfiguration.loadOrCreateAuthToken(environment: environment)
        let baseURL = AppRuntimeConfiguration.coreServiceURL(environment: environment)
        var messages: [Message] = []
        var cursor: MessageCursor?

        while messages.count < 5_000 {
            var components = URLComponents(
                url: baseURL.appending(path: "threads/thread-general/messages"),
                resolvingAgainstBaseURL: false
            )
            var query = [URLQueryItem(name: "limit", value: "200")]
            if let cursor {
                query.append(URLQueryItem(
                    name: "before_created_at",
                    value: PreciseDateCodec.string(from: cursor.createdAt)
                ))
                query.append(URLQueryItem(name: "before_message_id", value: cursor.messageID))
            }
            components?.queryItems = query
            guard let url = components?.url else { break }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode)
            else {
                break
            }
            let page = try JSONDecoder().decode([Message].self, from: data)
            guard !page.isEmpty else { break }
            messages.insert(contentsOf: page, at: 0)
            guard page.count == 200, let oldest = page.first else { break }
            cursor = MessageCursor(message: oldest)
        }
        return messages
    }
}
