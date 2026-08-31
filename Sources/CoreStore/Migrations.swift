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

        migrator.registerMigration("v2_search_and_events") { db in
            try db.create(table: "events") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("type", .text).notNull()
                table.column("project_id", .text).references("projects", column: "id", onDelete: .setNull)
                table.column("thread_id", .text).references("threads", column: "id", onDelete: .setNull)
                table.column("handoff_id", .text).references("handoffs", column: "id", onDelete: .setNull)
                table.column("actor_id", .text)
                table.column("body", .text).notNull()
                table.column("created_at", .datetime).notNull()
            }

            try db.create(virtualTable: "search_index", using: FTS5()) { table in
                table.column("object_id")
                table.column("object_type")
                table.column("body")
            }
        }

        migrator.registerMigration("v3_message_collaboration_metadata") { db in
            try db.alter(table: "messages") { table in
                table.add(column: "reply_to_message_id", .text)
                    .references("messages", column: "id", onDelete: .setNull)
                table.add(column: "mentioned_actor_ids", .text)
                    .notNull()
                    .defaults(to: "[]")
            }

            try db.create(
                index: "messages_on_thread_created_id",
                on: "messages",
                columns: ["thread_id", "created_at", "id"]
            )
        }

        migrator.registerMigration("v4_message_idempotency") { db in
            try db.alter(table: "messages") { table in
                table.add(column: "client_idempotency_key", .text)
            }

            try db.execute(
                sql: """
                CREATE UNIQUE INDEX messages_on_actor_idempotency_key
                ON messages (thread_id, actor_id, client_idempotency_key)
                WHERE client_idempotency_key IS NOT NULL
                """
            )
        }

        return migrator
    }
}
