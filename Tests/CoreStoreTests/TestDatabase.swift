import GRDB
@testable import CoreStore

enum TestDatabase {
    static func make() throws -> DatabaseQueue {
        try AppDatabase.makeInMemoryDatabase()
    }
}

extension DatabaseQueue {
    func tableNames() throws -> [String] {
        try read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT name
                FROM sqlite_master
                WHERE type = 'table'
                ORDER BY name
                """
            )
        }
    }
}
