import AppCore
import CloudKit
import Foundation
import RelayCloudClient

enum RelayCloudKitSchema {
    static let containerIdentifier = "iCloud.io.agentrelay.app"
    static let zoneName = "AgentRelay"
    static let recordType = "RelayEntity"
    static let workspaceID = "main"
    static let generalRoomID = "thread-general"
}

public enum RelayCloudKitLimits {
    public static let messageBodyCharacters = 100_000
    public static let roomNameCharacters = 80
    public static let roomTopicCharacters = 500
    public static let actorDisplayNameCharacters = 80
    public static let mentionedActors = 50
}

enum RelayCloudKitEntityKind: String, Codable, Sendable {
    case workspace
    case actor
    case room
    case message
    case readReceipt
    case presence
}

struct RelayCloudKitReadReceipt: Codable, Equatable, Sendable {
    let actorID: String
    let roomID: String
    let lastReadSequence: Int
    let updatedAt: Date
}

struct RelayCloudKitEntity: Codable, Equatable, Sendable {
    var id: String
    var kind: RelayCloudKitEntityKind
    var payload: Data
    var modifiedAt: Date
    var lastKnownRecordData: Data?

    var recordID: CKRecord.ID {
        CKRecord.ID(
            recordName: id,
            zoneID: CKRecordZone.ID(zoneName: RelayCloudKitSchema.zoneName)
        )
    }

    var lastKnownRecord: CKRecord? {
        get {
            guard let lastKnownRecordData else { return nil }
            do {
                let unarchiver = try NSKeyedUnarchiver(forReadingFrom: lastKnownRecordData)
                unarchiver.requiresSecureCoding = true
                return CKRecord(coder: unarchiver)
            } catch {
                return nil
            }
        }
        set {
            guard let newValue else {
                lastKnownRecordData = nil
                return
            }
            let archiver = NSKeyedArchiver(requiringSecureCoding: true)
            newValue.encodeSystemFields(with: archiver)
            lastKnownRecordData = archiver.encodedData
        }
    }

    mutating func setLastKnownRecordIfNewer(_ record: CKRecord) {
        if let localDate = lastKnownRecord?.modificationDate,
           let remoteDate = record.modificationDate,
           localDate >= remoteDate
        {
            return
        }
        lastKnownRecord = record
    }

    func populatedRecord() -> CKRecord {
        let record = lastKnownRecord ?? CKRecord(
            recordType: RelayCloudKitSchema.recordType,
            recordID: recordID
        )
        record.encryptedValues["kind"] = kind.rawValue as CKRecordValue
        record.encryptedValues["payload"] = payload as CKRecordValue
        record.encryptedValues["modifiedAt"] = modifiedAt as CKRecordValue
        return record
    }

    static func fromServerRecord(_ record: CKRecord) -> RelayCloudKitEntity? {
        guard record.recordType == RelayCloudKitSchema.recordType,
              let kindValue = record.encryptedValues["kind"] as? String,
              let kind = RelayCloudKitEntityKind(rawValue: kindValue),
              let payload = record.encryptedValues["payload"] as? Data
        else {
            return nil
        }
        var entity = RelayCloudKitEntity(
            id: record.recordID.recordName,
            kind: kind,
            payload: payload,
            modifiedAt: record.encryptedValues["modifiedAt"] as? Date
                ?? record.modificationDate
                ?? .distantPast,
            lastKnownRecordData: nil
        )
        entity.lastKnownRecord = record
        return entity
    }
}

struct RelayCloudKitCache: Codable {
    var entities: [String: RelayCloudKitEntity] = [:]
    var syncState: CKSyncEngine.State.Serialization?
    var accountRecordName: String?
}

enum RelayCloudKitEntityFactory {
    static func entity<T: Encodable>(
        id: String,
        kind: RelayCloudKitEntityKind,
        value: T,
        modifiedAt: Date = Date(),
        preserving existing: RelayCloudKitEntity? = nil
    ) throws -> RelayCloudKitEntity {
        var entity = RelayCloudKitEntity(
            id: id,
            kind: kind,
            payload: try encoder.encode(value),
            modifiedAt: modifiedAt,
            lastKnownRecordData: nil
        )
        entity.lastKnownRecordData = existing?.lastKnownRecordData
        return entity
    }

    static func decode<T: Decodable>(_ type: T.Type, from entity: RelayCloudKitEntity) -> T? {
        try? decoder.decode(type, from: entity.payload)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}

enum RelayCloudKitRecordName {
    static func workspace(_ id: String) -> String { "workspace:\(id)" }
    static func actor(_ id: String) -> String { "actor:\(id)" }
    static func room(_ id: String) -> String { "room:\(id)" }
    static func message(_ id: String) -> String { "message:\(id)" }
    static func readReceipt(actorID: String, roomID: String) -> String {
        "read:\(actorID):\(roomID)"
    }
    static func presence(actorID: String, deviceName: String) -> String {
        let safeDevice = deviceName
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        return "presence:\(actorID):\(String(safeDevice).prefix(80))"
    }
}

enum RelayCloudKitSnapshotBuilder {
    static func snapshot(
        from cache: RelayCloudKitCache,
        currentActorID: String
    ) -> RelaySyncSnapshot {
        let workspace = cache.entities.values
            .filter { $0.kind == .workspace }
            .compactMap { RelayCloudKitEntityFactory.decode(RelayWorkspace.self, from: $0) }
            .first
            ?? RelayWorkspace(id: RelayCloudKitSchema.workspaceID, name: "Bash's Agents")

        let actors = cache.entities.values
            .filter { $0.kind == .actor }
            .compactMap { RelayCloudKitEntityFactory.decode(RelayCloudActor.self, from: $0) }
            .sorted {
                if $0.role == "owner", $1.role != "owner" { return true }
                if $1.role == "owner", $0.role != "owner" { return false }
                return $0.id < $1.id
            }

        let messages = cache.entities.values
            .filter { $0.kind == .message }
            .compactMap { RelayCloudKitEntityFactory.decode(RelayCloudMessage.self, from: $0) }
            .sorted {
                $0.sequence == $1.sequence ? $0.id < $1.id : $0.sequence < $1.sequence
            }

        let allReceipts = cache.entities.values
            .filter { $0.kind == .readReceipt }
            .compactMap { RelayCloudKitEntityFactory.decode(RelayCloudKitReadReceipt.self, from: $0) }
        let currentReceipts = allReceipts.filter { $0.actorID == currentActorID }
        let receiptByRoom = Dictionary(
            currentReceipts.map { ($0.roomID, $0.lastReadSequence) },
            uniquingKeysWith: max
        )

        let rooms = cache.entities.values
            .filter { $0.kind == .room }
            .compactMap { RelayCloudKitEntityFactory.decode(RelayCloudRoom.self, from: $0) }
            .map { room in
                let roomMessages = messages.filter { $0.roomID == room.id }
                let latestSequence = roomMessages.last?.sequence
                let lastReadSequence = receiptByRoom[room.id]
                let updatedAt = max(room.updatedAt, roomMessages.last?.createdAt ?? room.updatedAt)
                return RelayCloudRoom(
                    id: room.id,
                    name: room.name,
                    title: room.title,
                    topic: room.topic,
                    isArchived: room.isArchived,
                    updatedAt: updatedAt,
                    lastReadSequence: lastReadSequence,
                    latestSequence: latestSequence,
                    unreadCount: roomMessages.filter { $0.sequence > (lastReadSequence ?? 0) }.count
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }

        let presence = cache.entities.values
            .filter { $0.kind == .presence }
            .compactMap { RelayCloudKitEntityFactory.decode(RelayPresence.self, from: $0) }
            .sorted { $0.lastSeenAt > $1.lastSeenAt }

        return RelaySyncSnapshot(
            workspace: workspace,
            currentActorID: currentActorID,
            actors: actors,
            rooms: rooms,
            messages: messages,
            readReceipts: currentReceipts.map {
                RelayReadReceipt(
                    roomID: $0.roomID,
                    lastReadSequence: $0.lastReadSequence,
                    updatedAt: $0.updatedAt
                )
            },
            presence: presence,
            nextCursor: messages.last?.sequence ?? 0,
            hasMore: false
        )
    }
}

enum RelayCloudKitConflictPolicy {
    static func localWins(
        _ local: RelayCloudKitEntity,
        over remote: RelayCloudKitEntity
    ) -> Bool {
        guard local.kind == remote.kind else {
            return local.modifiedAt > remote.modifiedAt
        }
        if local.kind == .readReceipt,
           let localReceipt = RelayCloudKitEntityFactory.decode(
            RelayCloudKitReadReceipt.self,
            from: local
           ),
           let remoteReceipt = RelayCloudKitEntityFactory.decode(
            RelayCloudKitReadReceipt.self,
            from: remote
           )
        {
            if localReceipt.lastReadSequence != remoteReceipt.lastReadSequence {
                return localReceipt.lastReadSequence > remoteReceipt.lastReadSequence
            }
            return localReceipt.updatedAt > remoteReceipt.updatedAt
        }
        return local.modifiedAt > remote.modifiedAt
    }
}
