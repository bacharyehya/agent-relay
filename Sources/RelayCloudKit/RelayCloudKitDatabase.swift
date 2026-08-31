import AppCore
import CloudKit
import Foundation
import RelayCloudClient

public enum RelayCloudKitDatabaseError: LocalizedError, Equatable {
    case iCloudAccountUnavailable
    case iCloudAccountRestricted
    case iCloudStatusUnknown
    case messageTooLong
    case invalidRoom
    case invalidActor

    public var errorDescription: String? {
        switch self {
        case .iCloudAccountUnavailable:
            "Sign in to iCloud on this device to use Agent Relay."
        case .iCloudAccountRestricted:
            "This iCloud account is restricted and cannot use Agent Relay sync."
        case .iCloudStatusUnknown:
            "Agent Relay could not verify iCloud right now. Try again in a moment."
        case .messageTooLong:
            "That message is too long for Agent Relay."
        case .invalidRoom:
            "Room names must be 1–80 characters and topics must be at most 500 characters."
        case .invalidActor:
            "Agent display names must be 1–80 characters."
        }
    }
}

public enum RelayCloudKitFailurePolicy {
    public static func allowsCachedMode(for error: Error) -> Bool {
        if let relayError = error as? RelayCloudKitDatabaseError {
            return relayError == .iCloudStatusUnknown
        }
        guard let cloudError = error as? CKError else { return false }
        switch cloudError.code {
        case .networkFailure, .networkUnavailable, .serviceUnavailable,
             .requestRateLimited, .zoneBusy, .operationCancelled:
            return true
        default:
            return false
        }
    }
}

public actor RelayCloudKitDatabase {
    public static let containerIdentifier = RelayCloudKitSchema.containerIdentifier
    public static let humanActorID = "bash"

    private struct Subscriber {
        let actorID: String
        let continuation: AsyncStream<RelaySyncSnapshot>.Continuation
    }

    private let container: CKContainer
    private let cacheURL: URL
    private let outboxDirectory: URL
    private let fileManager: FileManager
    private let automaticallySync: Bool
    private var cache: RelayCloudKitCache
    private var engineStorage: CKSyncEngine?
    private var subscribers: [UUID: Subscriber] = [:]

    private var syncEngine: CKSyncEngine {
        if let engineStorage { return engineStorage }
        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: cache.syncState,
            delegate: self
        )
        configuration.automaticallySync = automaticallySync
        let engine = CKSyncEngine(configuration)
        engineStorage = engine
        return engine
    }

    public init(
        container: CKContainer = CKContainer(identifier: "iCloud.io.agentrelay.app"),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        supportDirectory: URL? = nil,
        automaticallySync: Bool = true,
        fileManager: FileManager = .default
    ) throws {
        self.container = container
        self.fileManager = fileManager
        self.automaticallySync = automaticallySync
        self.cacheURL = try RelayCloudKitPaths.cacheURL(
            environment: environment,
            supportDirectory: supportDirectory,
            fileManager: fileManager
        )
        self.outboxDirectory = try RelayCloudKitPaths.outboxDirectory(
            environment: environment,
            supportDirectory: supportDirectory,
            fileManager: fileManager
        )
        self.cache = try RelayCloudKitPersistence.loadCache(
            from: self.cacheURL,
            fileManager: fileManager
        )
    }

    public func start(currentActorID: String = humanActorID, deviceName: String) async throws {
        try await prepareAccount()
        _ = syncEngine
        try await syncEngine.fetchChanges()
        if !hasWorkspace {
            try bootstrapPersonalWorkspace()
            try await syncEngine.sendChanges()
        }
        try await updatePresence(
            actorID: currentActorID,
            deviceName: deviceName,
            state: "online",
            sendImmediately: false
        )
        try? await syncEngine.sendChanges()
        publishSnapshots()
    }

    public func synchronize() async throws {
        try await prepareAccount()
        try await syncEngine.fetchChanges()
        let ingested = try drainOutboxWithoutSending()
        if ingested > 0 || !syncEngine.state.pendingRecordZoneChanges.isEmpty {
            try await syncEngine.sendChanges()
        }
        publishSnapshots()
    }

    public func snapshots(currentActorID: String = humanActorID) -> AsyncStream<RelaySyncSnapshot> {
        let identifier = UUID()
        return AsyncStream { continuation in
            subscribers[identifier] = Subscriber(actorID: currentActorID, continuation: continuation)
            continuation.yield(snapshot(currentActorID: currentActorID))
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeSubscriber(identifier) }
            }
        }
    }

    public func snapshot(currentActorID: String = humanActorID) -> RelaySyncSnapshot {
        RelayCloudKitSnapshotBuilder.snapshot(from: cache, currentActorID: currentActorID)
    }

    public func hasCachedWorkspace() -> Bool {
        hasWorkspace
    }

    @discardableResult
    public func postMessage(
        roomID: String,
        actorID: String,
        body: String,
        format: MessageFormat = .markdown,
        replyToMessageID: String? = nil,
        mentionedActorIDs: [String] = [],
        id: String = UUID().uuidString.lowercased()
    ) async throws -> RelayCloudMessage {
        guard !body.isEmpty, body.count <= RelayCloudKitLimits.messageBodyCharacters else {
            throw RelayCloudKitDatabaseError.messageTooLong
        }
        guard mentionedActorIDs.count <= RelayCloudKitLimits.mentionedActors else {
            throw RelayCloudKitDatabaseError.messageTooLong
        }
        let recordName = RelayCloudKitRecordName.message(id)
        if let existing = cache.entities[recordName],
           let message = RelayCloudKitEntityFactory.decode(RelayCloudMessage.self, from: existing)
        {
            return message
        }
        let now = Date()
        let latestSequence = cache.entities.values
            .filter { $0.kind == .message }
            .compactMap { RelayCloudKitEntityFactory.decode(RelayCloudMessage.self, from: $0)?.sequence }
            .max() ?? 0
        let message = RelayCloudMessage(
            id: id,
            sequence: max(latestSequence + 1, RelayCloudKitSequence.value(at: now)),
            roomID: roomID,
            threadID: roomID,
            actorID: actorID,
            body: body,
            format: format,
            replyToMessageID: replyToMessageID,
            mentionedActorIDs: mentionedActorIDs,
            createdAt: now,
            editedAt: nil
        )
        try saveEntity(
            id: recordName,
            kind: .message,
            value: message,
            modifiedAt: now
        )
        try await updatePresence(
            actorID: actorID,
            deviceName: ProcessInfo.processInfo.hostName,
            state: "online",
            sendImmediately: false
        )
        try? await syncEngine.sendChanges()
        return message
    }

    @discardableResult
    public func createRoom(name: String, topic: String) async throws -> RelayCloudRoom {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= RelayCloudKitLimits.roomNameCharacters,
              trimmedTopic.count <= RelayCloudKitLimits.roomTopicCharacters
        else {
            throw RelayCloudKitDatabaseError.invalidRoom
        }
        let slug = trimmed.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let baseID = slug.isEmpty ? "room" : "room-\(slug)"
        let id = cache.entities[RelayCloudKitRecordName.room(baseID)] == nil
            ? baseID
            : "\(baseID)-\(UUID().uuidString.lowercased().prefix(8))"
        let now = Date()
        let room = RelayCloudRoom(
            id: id,
            name: slug.isEmpty ? id : slug,
            title: trimmed,
            topic: trimmedTopic,
            isArchived: false,
            updatedAt: now
        )
        try saveEntity(id: RelayCloudKitRecordName.room(id), kind: .room, value: room, modifiedAt: now)
        try? await syncEngine.sendChanges()
        return room
    }

    @discardableResult
    public func importMessages(_ messages: [RelayCloudMessage]) async throws -> Int {
        var imported = 0
        var pending: [CKSyncEngine.PendingRecordZoneChange] = []
        for message in messages {
            let recordName = RelayCloudKitRecordName.message(message.id)
            guard cache.entities[recordName] == nil else { continue }
            let entity = try RelayCloudKitEntityFactory.entity(
                id: recordName,
                kind: .message,
                value: message,
                modifiedAt: message.editedAt ?? message.createdAt
            )
            cache.entities[recordName] = entity
            pending.append(.saveRecord(entity.recordID))
            imported += 1
        }
        guard imported > 0 else { return 0 }
        syncEngine.state.add(pendingRecordZoneChanges: pending)
        try persist()
        publishSnapshots()
        try? await syncEngine.sendChanges()
        return imported
    }

    @discardableResult
    public func addAgent(actorID: String, displayName: String) async throws -> RelayCloudActor {
        guard RelayCloudKitAgentInstaller.isSafeActorID(actorID) else {
            throw RelayCloudKitAgentInstallerError.invalidActorID
        }
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              trimmedName.count <= RelayCloudKitLimits.actorDisplayNameCharacters
        else {
            throw RelayCloudKitDatabaseError.invalidActor
        }
        let actor = RelayCloudActor(
            id: actorID,
            type: .agent,
            displayName: trimmedName,
            role: RelayAgentProfile.profile(for: actorID).role,
            status: .active
        )
        try saveEntity(
            id: RelayCloudKitRecordName.actor(actorID),
            kind: .actor,
            value: actor
        )
        try? await syncEngine.sendChanges()
        return actor
    }

    public func markRead(roomID: String, actorID: String, sequence: Int) async throws {
        let id = RelayCloudKitRecordName.readReceipt(actorID: actorID, roomID: roomID)
        let existingSequence = cache.entities[id]
            .flatMap { RelayCloudKitEntityFactory.decode(RelayCloudKitReadReceipt.self, from: $0) }
            .map(\.lastReadSequence) ?? 0
        guard sequence > existingSequence else { return }
        let now = Date()
        let receipt = RelayCloudKitReadReceipt(
            actorID: actorID,
            roomID: roomID,
            lastReadSequence: sequence,
            updatedAt: now
        )
        try saveEntity(id: id, kind: .readReceipt, value: receipt, modifiedAt: now)
        try? await syncEngine.sendChanges()
    }

    @discardableResult
    public func drainOutbox() async throws -> Int {
        let count = try drainOutboxWithoutSending()
        if count > 0 {
            try? await syncEngine.sendChanges()
        }
        return count
    }

    public func resetLocalCache() throws {
        cache = RelayCloudKitCache()
        engineStorage = nil
        try persist()
        publishSnapshots()
    }

    private var hasWorkspace: Bool {
        cache.entities.values.contains { $0.kind == .workspace }
    }

    private func prepareAccount() async throws {
        switch try await container.accountStatus() {
        case .available:
            break
        case .noAccount:
            throw RelayCloudKitDatabaseError.iCloudAccountUnavailable
        case .restricted:
            throw RelayCloudKitDatabaseError.iCloudAccountRestricted
        case .couldNotDetermine, .temporarilyUnavailable:
            throw RelayCloudKitDatabaseError.iCloudStatusUnknown
        @unknown default:
            throw RelayCloudKitDatabaseError.iCloudStatusUnknown
        }
        let currentAccount = try await container.userRecordID().recordName
        if let previousAccount = cache.accountRecordName,
           previousAccount != currentAccount
        {
            cache = RelayCloudKitCache(accountRecordName: currentAccount)
            engineStorage = nil
            try persist()
            publishSnapshots()
        } else if cache.accountRecordName == nil {
            cache.accountRecordName = currentAccount
            try persist()
        }
    }

    private func bootstrapPersonalWorkspace() throws {
        let now = Date()
        let workspace = RelayWorkspace(id: RelayCloudKitSchema.workspaceID, name: "Bash's Agents")
        let owner = RelayCloudActor(
            id: Self.humanActorID,
            type: .human,
            displayName: "Bash",
            role: "owner",
            status: .active
        )
        let room = RelayCloudRoom(
            id: RelayCloudKitSchema.generalRoomID,
            name: "general",
            title: "General",
            topic: "Bash and the agents work together here.",
            isArchived: false,
            updatedAt: now
        )
        var entities: [RelayCloudKitEntity] = [
            try RelayCloudKitEntityFactory.entity(
                id: RelayCloudKitRecordName.workspace(workspace.id),
                kind: .workspace,
                value: workspace,
                modifiedAt: now
            ),
            try RelayCloudKitEntityFactory.entity(
                id: RelayCloudKitRecordName.actor(owner.id),
                kind: .actor,
                value: owner,
                modifiedAt: now
            ),
            try RelayCloudKitEntityFactory.entity(
                id: RelayCloudKitRecordName.room(room.id),
                kind: .room,
                value: room,
                modifiedAt: now
            ),
        ]
        entities.append(contentsOf: try RelayAgentProfile.known.map { profile in
            try RelayCloudKitEntityFactory.entity(
                id: RelayCloudKitRecordName.actor(profile.id),
                kind: .actor,
                value: RelayCloudActor(
                    id: profile.id,
                    type: .agent,
                    displayName: profile.displayName,
                    role: profile.role,
                    status: .active
                ),
                modifiedAt: now
            )
        })
        for entity in entities { cache.entities[entity.id] = entity }
        syncEngine.state.add(
            pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneName: RelayCloudKitSchema.zoneName))]
        )
        syncEngine.state.add(
            pendingRecordZoneChanges: entities.map { .saveRecord($0.recordID) }
        )
        try persist()
        publishSnapshots()
    }

    private func updatePresence(
        actorID: String,
        deviceName: String,
        state: String,
        sendImmediately: Bool
    ) async throws {
        let now = Date()
        let presence = RelayPresence(
            actorID: actorID,
            deviceName: deviceName,
            state: state,
            lastSeenAt: now
        )
        try saveEntity(
            id: RelayCloudKitRecordName.presence(actorID: actorID, deviceName: deviceName),
            kind: .presence,
            value: presence,
            modifiedAt: now
        )
        if sendImmediately { try await syncEngine.sendChanges() }
    }

    private func saveEntity<T: Encodable>(
        id: String,
        kind: RelayCloudKitEntityKind,
        value: T,
        modifiedAt: Date = Date()
    ) throws {
        let entity = try RelayCloudKitEntityFactory.entity(
            id: id,
            kind: kind,
            value: value,
            modifiedAt: modifiedAt,
            preserving: cache.entities[id]
        )
        cache.entities[id] = entity
        syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(entity.recordID)])
        try persist()
        publishSnapshots()
    }

    private func drainOutboxWithoutSending() throws -> Int {
        let urls = try fileManager.contentsOfDirectory(
            at: outboxDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !urls.isEmpty else { return 0 }

        var ingested = 0
        var consumed: [URL] = []
        var pending: [CKSyncEngine.PendingRecordZoneChange] = []
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let outbox = try? RelayCloudKitPersistence.decoder.decode(
                    RelayCloudKitOutboxMessage.self,
                    from: data
                  )
            else {
                continue
            }
            let recordName = RelayCloudKitRecordName.message(outbox.id)
            if cache.entities[recordName] == nil {
                let entity = try RelayCloudKitEntityFactory.entity(
                    id: recordName,
                    kind: .message,
                    value: outbox.message,
                    modifiedAt: outbox.createdAt
                )
                cache.entities[recordName] = entity
                pending.append(.saveRecord(entity.recordID))
                ingested += 1
            }
            consumed.append(url)
        }
        if !pending.isEmpty {
            syncEngine.state.add(pendingRecordZoneChanges: pending)
            try persist()
            publishSnapshots()
        }
        for url in consumed { try? fileManager.removeItem(at: url) }
        return ingested
    }

    private func persist() throws {
        try RelayCloudKitPersistence.atomicWrite(
            RelayCloudKitPersistence.encoder.encode(cache),
            to: cacheURL,
            fileManager: fileManager
        )
    }

    private func publishSnapshots() {
        for subscriber in subscribers.values {
            subscriber.continuation.yield(snapshot(currentActorID: subscriber.actorID))
        }
    }

    private func removeSubscriber(_ identifier: UUID) {
        subscribers[identifier] = nil
    }
}

extension RelayCloudKitDatabase: CKSyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            cache.syncState = update.stateSerialization
            try? persist()

        case .accountChange(let change):
            handleAccountChange(change, syncEngine: syncEngine)

        case .fetchedDatabaseChanges(let changes):
            handleFetchedDatabaseChanges(changes)

        case .fetchedRecordZoneChanges(let changes):
            handleFetchedRecordZoneChanges(changes, syncEngine: syncEngine)

        case .sentRecordZoneChanges(let changes):
            handleSentRecordZoneChanges(changes, syncEngine: syncEngine)

        case .sentDatabaseChanges,
             .willFetchChanges,
             .willFetchRecordZoneChanges,
             .didFetchRecordZoneChanges,
             .didFetchChanges,
             .willSendChanges,
             .didSendChanges:
            break

        @unknown default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = syncEngine.state.pendingRecordZoneChanges.filter {
            context.options.scope.contains($0)
        }
        let entities = cache.entities
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            guard let entity = entities[recordID.recordName] else {
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }
            return entity.populatedRecord()
        }
    }

    private func handleAccountChange(
        _ event: CKSyncEngine.Event.AccountChange,
        syncEngine: CKSyncEngine
    ) {
        switch event.changeType {
        case .signIn:
            break
        case .switchAccounts, .signOut:
            cache = RelayCloudKitCache()
            try? persist()
            publishSnapshots()
        @unknown default:
            break
        }
    }

    private func handleFetchedDatabaseChanges(
        _ event: CKSyncEngine.Event.FetchedDatabaseChanges
    ) {
        guard event.deletions.contains(where: { $0.zoneID.zoneName == RelayCloudKitSchema.zoneName }) else {
            return
        }
        cache.entities = [:]
        try? persist()
        publishSnapshots()
    }

    private func handleFetchedRecordZoneChanges(
        _ event: CKSyncEngine.Event.FetchedRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) {
        var pendingSaves: [CKSyncEngine.PendingRecordZoneChange] = []
        for modification in event.modifications {
            let record = modification.record
            guard var remote = RelayCloudKitEntity.fromServerRecord(record) else { continue }
            if var local = cache.entities[remote.id],
               RelayCloudKitConflictPolicy.localWins(local, over: remote)
            {
                local.setLastKnownRecordIfNewer(record)
                cache.entities[remote.id] = local
                pendingSaves.append(.saveRecord(local.recordID))
            } else {
                remote.setLastKnownRecordIfNewer(record)
                cache.entities[remote.id] = remote
            }
        }
        for deletion in event.deletions {
            cache.entities[deletion.recordID.recordName] = nil
        }
        if !pendingSaves.isEmpty {
            syncEngine.state.add(pendingRecordZoneChanges: pendingSaves)
        }
        if !event.modifications.isEmpty || !event.deletions.isEmpty {
            try? persist()
            publishSnapshots()
        }
    }

    private func handleSentRecordZoneChanges(
        _ event: CKSyncEngine.Event.SentRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) {
        var pendingRecords: [CKSyncEngine.PendingRecordZoneChange] = []
        var pendingDatabase: [CKSyncEngine.PendingDatabaseChange] = []

        for savedRecord in event.savedRecords {
            let id = savedRecord.recordID.recordName
            if var entity = cache.entities[id] {
                entity.setLastKnownRecordIfNewer(savedRecord)
                cache.entities[id] = entity
            }
        }

        for failure in event.failedRecordSaves {
            let id = failure.record.recordID.recordName
            var clearServerRecord = false
            switch failure.error.code {
            case .serverRecordChanged:
                if let serverRecord = failure.error.serverRecord,
                   var remote = RelayCloudKitEntity.fromServerRecord(serverRecord)
                {
                    if var local = cache.entities[id],
                       RelayCloudKitConflictPolicy.localWins(local, over: remote)
                    {
                        local.setLastKnownRecordIfNewer(serverRecord)
                        cache.entities[id] = local
                        pendingRecords.append(.saveRecord(failure.record.recordID))
                    } else {
                        remote.setLastKnownRecordIfNewer(serverRecord)
                        cache.entities[id] = remote
                    }
                }
            case .zoneNotFound:
                pendingDatabase.append(.saveZone(CKRecordZone(zoneID: failure.record.recordID.zoneID)))
                pendingRecords.append(.saveRecord(failure.record.recordID))
                clearServerRecord = true
            case .unknownItem:
                pendingRecords.append(.saveRecord(failure.record.recordID))
                clearServerRecord = true
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                 .notAuthenticated, .operationCancelled:
                break
            default:
                break
            }
            if clearServerRecord, var entity = cache.entities[id] {
                entity.lastKnownRecord = nil
                cache.entities[id] = entity
            }
        }

        syncEngine.state.add(pendingDatabaseChanges: pendingDatabase)
        syncEngine.state.add(pendingRecordZoneChanges: pendingRecords)
        try? persist()
        publishSnapshots()
    }
}
