import GRDB

public enum AppMigrations {
    public static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "projects") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("title", .text).notNull()
                table.column("summary", .text).notNull().defaults(to: "")
                table.column("status", .text).notNull()
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "threads") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("project_id", .text)
                    .notNull()
                    .indexed()
                    .references("projects", column: "id", onDelete: .cascade)
                table.column("title", .text).notNull()
                table.column("intent_type", .text).notNull()
                table.column("status", .text).notNull()
                table.column("created_by", .text).notNull()
                table.column("assigned_actor_ids", .text).notNull().defaults(to: "[]")
                table.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "messages") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("thread_id", .text)
                    .notNull()
                    .indexed()
                    .references("threads", column: "id", onDelete: .cascade)
                table.column("actor_id", .text).notNull()
                table.column("body", .text).notNull()
                table.column("format", .text).notNull()
                table.column("created_at", .datetime).notNull()
            }

            try db.create(table: "handoffs") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("thread_id", .text)
                    .notNull()
                    .indexed()
                    .references("threads", column: "id", onDelete: .cascade)
                table.column("title", .text).notNull()
                table.column("summary", .text).notNull().defaults(to: "")
                table.column("ask", .text).notNull()
                table.column("status", .text).notNull()
                table.column("priority", .text).notNull()
                table.column("created_by", .text).notNull()
                table.column("assigned_to", .text).notNull()
                table.column("source_refs", .text).notNull().defaults(to: "[]")
                table.column("resolution", .text)
            }
        }

        return migrator
    }
}
