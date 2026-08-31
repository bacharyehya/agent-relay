PRAGMA foreign_keys = ON;

CREATE TABLE workspaces (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    owner_actor_id TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE TABLE actors (
    id TEXT NOT NULL,
    workspace_id TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('human', 'agent')),
    display_name TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('owner', 'member')),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'unavailable')),
    created_at TEXT NOT NULL,
    PRIMARY KEY (workspace_id, id),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE access_tokens (
    id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    actor_id TEXT NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    device_name TEXT NOT NULL,
    created_at TEXT NOT NULL,
    last_used_at TEXT,
    revoked_at TEXT,
    FOREIGN KEY (workspace_id, actor_id) REFERENCES actors(workspace_id, id) ON DELETE CASCADE
);

CREATE INDEX access_tokens_actor ON access_tokens(workspace_id, actor_id);

CREATE TABLE invitations (
    id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('human-device', 'agent')),
    actor_id TEXT NOT NULL,
    display_name TEXT NOT NULL,
    code_hash TEXT NOT NULL UNIQUE,
    created_by TEXT NOT NULL,
    created_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    used_at TEXT,
    FOREIGN KEY (workspace_id, created_by) REFERENCES actors(workspace_id, id) ON DELETE CASCADE
);

CREATE INDEX invitations_workspace_expiry ON invitations(workspace_id, expires_at);

CREATE TABLE rooms (
    id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    name TEXT NOT NULL,
    topic TEXT NOT NULL DEFAULT '',
    is_archived INTEGER NOT NULL DEFAULT 0,
    created_by TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE (workspace_id, name),
    FOREIGN KEY (workspace_id, created_by) REFERENCES actors(workspace_id, id) ON DELETE RESTRICT
);

CREATE INDEX rooms_workspace_updated ON rooms(workspace_id, updated_at DESC);

CREATE TABLE messages (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
    id TEXT NOT NULL UNIQUE,
    workspace_id TEXT NOT NULL,
    room_id TEXT NOT NULL,
    actor_id TEXT NOT NULL,
    body TEXT NOT NULL,
    format TEXT NOT NULL DEFAULT 'markdown' CHECK (format IN ('markdown', 'plainText')),
    reply_to_message_id TEXT,
    client_idempotency_key TEXT NOT NULL,
    created_at TEXT NOT NULL,
    edited_at TEXT,
    FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE,
    FOREIGN KEY (workspace_id, actor_id) REFERENCES actors(workspace_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (reply_to_message_id) REFERENCES messages(id) ON DELETE SET NULL,
    UNIQUE (room_id, actor_id, client_idempotency_key)
);

CREATE INDEX messages_room_sequence ON messages(room_id, sequence DESC);
CREATE INDEX messages_workspace_sequence ON messages(workspace_id, sequence ASC);
CREATE INDEX messages_workspace_created ON messages(workspace_id, created_at DESC);

CREATE TABLE message_mentions (
    message_id TEXT NOT NULL,
    actor_id TEXT NOT NULL,
    workspace_id TEXT NOT NULL,
    PRIMARY KEY (message_id, actor_id),
    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
    FOREIGN KEY (workspace_id, actor_id) REFERENCES actors(workspace_id, id) ON DELETE CASCADE
);

CREATE INDEX mentions_actor_message ON message_mentions(workspace_id, actor_id, message_id);

CREATE TABLE read_receipts (
    workspace_id TEXT NOT NULL,
    actor_id TEXT NOT NULL,
    room_id TEXT NOT NULL,
    last_read_sequence INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL,
    PRIMARY KEY (workspace_id, actor_id, room_id),
    FOREIGN KEY (workspace_id, actor_id) REFERENCES actors(workspace_id, id) ON DELETE CASCADE,
    FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE
);

CREATE TABLE presence (
    workspace_id TEXT NOT NULL,
    actor_id TEXT NOT NULL,
    device_name TEXT NOT NULL,
    state TEXT NOT NULL CHECK (state IN ('online', 'away', 'offline')),
    last_seen_at TEXT NOT NULL,
    PRIMARY KEY (workspace_id, actor_id, device_name),
    FOREIGN KEY (workspace_id, actor_id) REFERENCES actors(workspace_id, id) ON DELETE CASCADE
);

CREATE INDEX presence_workspace_seen ON presence(workspace_id, last_seen_at DESC);
