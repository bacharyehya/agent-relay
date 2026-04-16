import Foundation
import GRDB

public enum AppDatabase {
    public static func makeInMemoryDatabase() throws -> DatabaseQueue {
        try makeDatabaseQueue(path: ":memory:")
    }

    public static func makeDatabaseQueue(path: String) throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let dbQueue = try DatabaseQueue(path: path, configuration: configuration)
        try migrate(dbQueue)
        return dbQueue
    }

    public static func migrate(_ dbQueue: DatabaseQueue) throws {
        try AppMigrations.makeMigrator().migrate(dbQueue)
    }
}
