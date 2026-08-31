import {
  RelayAuthError,
  RelayInputError,
  json,
  messageFromRow,
  normalizeActorID,
  normalizeRoomName,
  optionalText,
  parseCursor,
  parseLimit,
  randomInviteCode,
  randomToken,
  readJSON,
  requiredText,
  sha256,
  uniqueStrings,
} from "./lib.js";

const serviceVersion = "0.2.0";

export default {
  async fetch(request, env, context) {
    const requestID = crypto.randomUUID();
    try {
      return await route(request, env, context);
    } catch (error) {
      if (error instanceof RelayInputError || error instanceof RelayAuthError) {
        return json({ error: error.message, requestID }, error.status);
      }
      console.error("agent-relay-request-failed", requestID, error?.name ?? "Error", error?.message ?? "unknown");
      return json({ error: "The Relay service could not complete this request.", requestID }, 500);
    }
  },
};

async function route(request, env, context) {
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, "") || "/";
  const isReadRequest = request.method === "GET" || request.method === "HEAD";

  if (isReadRequest && (path === "/" || path === "/health")) {
    return json({ status: "ok", service: "agent-relay-personal", version: serviceVersion });
  }

  if (isReadRequest && path === "/privacy") {
    return documentResponse("Privacy Policy", privacyPolicyBody());
  }

  if (isReadRequest && path === "/support") {
    return documentResponse("Support", supportBody());
  }

  if (request.method === "POST" && path === "/v1/bootstrap") {
    return bootstrap(request, env);
  }

  if (request.method === "POST" && path === "/v1/enroll") {
    return enroll(request, env);
  }

  const auth = await authenticate(request, env, context);

  if (request.method === "GET" && path === "/v1/me") return getMe(auth);
  if (request.method === "GET" && path === "/v1/sync") return sync(url, env, auth);
  if (request.method === "GET" && path === "/v1/actors") return listActors(env, auth);
  if (request.method === "GET" && path === "/v1/rooms") return listRooms(env, auth);
  if (request.method === "POST" && path === "/v1/rooms") return createRoom(request, env, auth);
  if (request.method === "GET" && path === "/v1/mentions") return listMentions(url, env, auth);
  if (request.method === "GET" && path === "/v1/search") return searchMessages(url, env, auth);
  if (request.method === "GET" && path === "/v1/devices") return listDevices(env, auth);
  if (request.method === "POST" && path === "/v1/invitations") return createInvitation(request, env, auth);
  if (request.method === "POST" && path === "/v1/presence") return updatePresence(request, env, auth);

  const roomMessagesMatch = path.match(/^\/v1\/rooms\/([^/]+)\/messages$/);
  if (roomMessagesMatch && request.method === "GET") {
    return listMessages(url, env, auth, decodeURIComponent(roomMessagesMatch[1]));
  }
  if (roomMessagesMatch && request.method === "POST") {
    return postMessage(request, env, auth, decodeURIComponent(roomMessagesMatch[1]));
  }

  const roomReadMatch = path.match(/^\/v1\/rooms\/([^/]+)\/read$/);
  if (roomReadMatch && request.method === "POST") {
    return markRoomRead(request, env, auth, decodeURIComponent(roomReadMatch[1]));
  }

  const revokeMatch = path.match(/^\/v1\/devices\/([^/]+)\/revoke$/);
  if (revokeMatch && request.method === "POST") {
    return revokeDevice(env, auth, decodeURIComponent(revokeMatch[1]));
  }

  return json({ error: "Route not found" }, 404);
}

function documentResponse(title, body) {
  const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="color-scheme" content="dark light">
  <title>${title} · Agent Relay</title>
  <style>
    :root { color-scheme: dark; font: 17px/1.6 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; background: #0b0b0c; color: #f5f5f7; }
    body { margin: 0; }
    main { box-sizing: border-box; width: min(720px, 100%); margin: 0 auto; padding: 64px 24px 96px; }
    .mark { display: inline-grid; place-items: center; width: 44px; height: 44px; margin-bottom: 28px; border: 1px solid #3a3a3c; border-radius: 13px; background: #fff; color: #000; font-weight: 800; }
    h1 { margin: 0 0 8px; font-size: clamp(36px, 8vw, 54px); line-height: 1.05; letter-spacing: -.04em; }
    h2 { margin: 42px 0 8px; font-size: 21px; letter-spacing: -.01em; }
    p, li { color: #c7c7cc; }
    .lede { margin-top: 8px; font-size: 20px; color: #f5f5f7; }
    .meta { color: #8e8e93; }
    a { color: inherit; text-underline-offset: 3px; }
    @media (prefers-color-scheme: light) { :root { color-scheme: light; background: #f5f5f7; color: #111; } p, li { color: #3a3a3c; } .lede { color: #111; } .mark { background: #000; color: #fff; } }
  </style>
</head>
<body><main><div class="mark" aria-hidden="true">AR</div>${body}</main></body>
</html>`;
  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=300",
      "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      "permissions-policy": "camera=(), microphone=(), geolocation=()",
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
      "x-frame-options": "DENY",
    },
  });
}

function privacyPolicyBody() {
  return `<h1>Privacy Policy</h1>
  <p class="lede">Agent Relay is a private workspace where one human and their invited AI agents communicate.</p>
  <p class="meta">Effective August 31, 2026</p>
  <h2>Information Agent Relay stores</h2>
  <ul>
    <li>Your display name, workspace membership, rooms, device names, and presence state.</li>
    <li>Messages, replies, mentions, read state, and message timestamps that you or your agents send.</li>
    <li>Authentication tokens in one-way hashed form. Raw credentials are not stored by the service.</li>
  </ul>
  <h2>How the information is used</h2>
  <p>The service uses this information only to authenticate your devices, synchronize your private workspace, deliver messages, show unread activity, and operate and secure Agent Relay.</p>
  <h2>Infrastructure and sharing</h2>
  <p>Agent Relay currently runs on Bashar Yehia’s personal Cloudflare account. Cloudflare processes the service traffic and stores the application database as our infrastructure provider. Agent Relay does not sell personal information, run advertising, use cross-app tracking, or share workspace content with data brokers.</p>
  <h2>AI agents</h2>
  <p>Messages that mention a connected agent are processed by that agent on its enrolled Mac. Agent Relay itself does not require an OpenAI API key. The agent’s separate ChatGPT or Codex account relationship is governed by that provider’s terms and privacy policy.</p>
  <h2>Retention and control</h2>
  <p>Workspace content remains available until the workspace owner deletes it or requests deletion. Device credentials can be revoked. For access, correction, export, or deletion requests, contact the address below.</p>
  <h2>Children</h2>
  <p>Agent Relay is not intended for children under 13.</p>
  <h2>Contact</h2>
  <p><a href="mailto:bacharyehya@gmail.com">bacharyehya@gmail.com</a></p>`;
}

function supportBody() {
  return `<h1>Agent Relay Support</h1>
  <p class="lede">Help for the private Agent Relay beta on Mac, iPhone, and iPad.</p>
  <h2>Getting help</h2>
  <p>Email <a href="mailto:bacharyehya@gmail.com">bacharyehya@gmail.com</a> with the device you are using and a short description of what happened. Never include an invitation code or Relay access token.</p>
  <h2>Joining another device</h2>
  <p>On the owner Mac, open Settings and create a one-time human-device invitation. Enter that code on the new device. Invitations expire after one hour and can be used once.</p>
  <h2>Agent connection</h2>
  <p>Agents run on an enrolled Mac and communicate through the same private rooms as the human client. The iPhone app is a secure chat client and does not execute agents locally.</p>
  <h2>Privacy</h2>
  <p>Read the <a href="/privacy">Agent Relay Privacy Policy</a>.</p>`;
}

async function bootstrap(request, env) {
  const configuredSecret = String(env.BOOTSTRAP_SECRET ?? "").trim();
  if (!configuredSecret) throw new RelayAuthError("Workspace bootstrap is not configured", 503);
  const suppliedSecret = request.headers.get("x-relay-bootstrap-key") ?? "";
  if (!(await equalSecrets(configuredSecret, suppliedSecret))) {
    throw new RelayAuthError("Invalid bootstrap key", 403);
  }

  const existing = await env.DB.prepare("SELECT COUNT(*) AS count FROM workspaces").first();
  if (Number(existing?.count ?? 0) > 0) {
    throw new RelayInputError("This Relay service already has an owner workspace", 409);
  }

  const payload = await readJSON(request);
  const workspaceName = requiredText(payload.workspaceName ?? "Agent Relay", "workspaceName", 80);
  const displayName = requiredText(payload.displayName ?? "Bash", "displayName", 80);
  const deviceName = requiredText(payload.deviceName ?? "Owner Mac", "deviceName", 120);
  const actorID = normalizeActorID(payload.actorID ?? "bash");
  const now = new Date().toISOString();
  const workspaceID = crypto.randomUUID();
  const tokenID = crypto.randomUUID();
  const roomID = crypto.randomUUID();
  const token = randomToken("relay_owner");
  const tokenHash = await sha256(token);

  await env.DB.batch([
    env.DB.prepare(
      "INSERT INTO workspaces (id, name, owner_actor_id, created_at) VALUES (?, ?, ?, ?)",
    ).bind(workspaceID, workspaceName, actorID, now),
    env.DB.prepare(
      "INSERT INTO actors (id, workspace_id, type, display_name, role, status, created_at) VALUES (?, ?, 'human', ?, 'owner', 'active', ?)",
    ).bind(actorID, workspaceID, displayName, now),
    env.DB.prepare(
      "INSERT INTO access_tokens (id, workspace_id, actor_id, token_hash, device_name, created_at) VALUES (?, ?, ?, ?, ?, ?)",
    ).bind(tokenID, workspaceID, actorID, tokenHash, deviceName, now),
    env.DB.prepare(
      "INSERT INTO rooms (id, workspace_id, name, topic, created_by, created_at, updated_at) VALUES (?, ?, 'general', 'The shared room for Bash and every agent.', ?, ?, ?)",
    ).bind(roomID, workspaceID, actorID, now, now),
  ]);

  return json(
    {
      workspace: { id: workspaceID, name: workspaceName },
      actor: actorJSON({ id: actorID, type: "human", display_name: displayName, role: "owner", status: "active" }),
      device: { id: tokenID, name: deviceName },
      token,
      room: roomJSON({ id: roomID, name: "general", topic: "The shared room for Bash and every agent.", is_archived: 0, updated_at: now }),
    },
    201,
  );
}

async function createInvitation(request, env, auth) {
  requireOwner(auth);
  const payload = await readJSON(request);
  const kind = payload.kind === "human-device" ? "human-device" : payload.kind === "agent" ? "agent" : null;
  if (!kind) throw new RelayInputError("kind must be human-device or agent");

  let actorID;
  let displayName;
  if (kind === "human-device") {
    actorID = auth.actorID;
    displayName = auth.displayName;
  } else {
    actorID = normalizeActorID(payload.actorID);
    displayName = requiredText(payload.displayName, "displayName", 80);
    const existing = await env.DB.prepare(
      "SELECT id, type, display_name FROM actors WHERE workspace_id = ? AND id = ?",
    ).bind(auth.workspaceID, actorID).first();
    if (existing?.type && existing.type !== "agent") {
      throw new RelayInputError("That actor ID belongs to a human and cannot be enrolled as an agent", 409);
    }
    if (existing?.display_name) displayName = existing.display_name;
  }

  const code = randomInviteCode();
  const codeHash = await sha256(code.replace(/-/g, "").toUpperCase());
  const now = new Date();
  const expiresAt = new Date(now.getTime() + 60 * 60 * 1000);
  const invitationID = crypto.randomUUID();
  await env.DB.prepare(
    `INSERT INTO invitations
     (id, workspace_id, kind, actor_id, display_name, code_hash, created_by, created_at, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  ).bind(
    invitationID,
    auth.workspaceID,
    kind,
    actorID,
    displayName,
    codeHash,
    auth.actorID,
    now.toISOString(),
    expiresAt.toISOString(),
  ).run();

  return json({ id: invitationID, kind, actorID, displayName, code, expiresAt: expiresAt.toISOString() }, 201);
}

async function enroll(request, env) {
  const payload = await readJSON(request);
  const rawCode = requiredText(payload.code, "code", 64).replace(/-/g, "").toUpperCase();
  const codeHash = await sha256(rawCode);
  const invitation = await env.DB.prepare(
    `SELECT id, workspace_id, kind, actor_id, display_name, expires_at
     FROM invitations WHERE code_hash = ? AND used_at IS NULL`,
  ).bind(codeHash).first();
  if (!invitation || Date.parse(invitation.expires_at) <= Date.now()) {
    throw new RelayAuthError("Invitation is invalid or expired", 403);
  }

  const deviceName = requiredText(payload.deviceName, "deviceName", 120);
  const now = new Date().toISOString();
  const tokenID = crypto.randomUUID();
  const token = randomToken(invitation.kind === "agent" ? "relay_agent" : "relay_human");
  const tokenHash = await sha256(token);
  const statements = [];

  if (invitation.kind === "agent") {
    const existingAgent = await env.DB.prepare(
      "SELECT id, type FROM actors WHERE workspace_id = ? AND id = ?",
    ).bind(invitation.workspace_id, invitation.actor_id).first();
    if (existingAgent?.type && existingAgent.type !== "agent") {
      throw new RelayAuthError("The invited identity is no longer an agent", 403);
    }
    if (!existingAgent) {
      statements.push(
        env.DB.prepare(
          "INSERT INTO actors (id, workspace_id, type, display_name, role, status, created_at) VALUES (?, ?, 'agent', ?, 'member', 'active', ?)",
        ).bind(invitation.actor_id, invitation.workspace_id, invitation.display_name, now),
      );
    }
  } else {
    const human = await env.DB.prepare(
      "SELECT id FROM actors WHERE workspace_id = ? AND id = ? AND type = 'human'",
    ).bind(invitation.workspace_id, invitation.actor_id).first();
    if (!human) throw new RelayAuthError("The invited human identity no longer exists", 403);
  }

  statements.push(
    env.DB.prepare(
      "INSERT INTO access_tokens (id, workspace_id, actor_id, token_hash, device_name, created_at) VALUES (?, ?, ?, ?, ?, ?)",
    ).bind(tokenID, invitation.workspace_id, invitation.actor_id, tokenHash, deviceName, now),
    env.DB.prepare("UPDATE invitations SET used_at = ? WHERE id = ? AND used_at IS NULL").bind(now, invitation.id),
  );
  await env.DB.batch(statements);

  const workspace = await env.DB.prepare("SELECT id, name FROM workspaces WHERE id = ?").bind(invitation.workspace_id).first();
  return json(
    {
      workspace,
      actor: {
        id: invitation.actor_id,
        type: invitation.kind === "agent" ? "agent" : "human",
        displayName: invitation.display_name,
        role: invitation.kind === "agent" ? "member" : "owner",
        status: "active",
      },
      device: { id: tokenID, name: deviceName },
      token,
    },
    201,
  );
}

async function authenticate(request, env, context) {
  const authorization = request.headers.get("authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) throw new RelayAuthError();
  const tokenHash = await sha256(match[1]);
  const row = await env.DB.prepare(
    `SELECT t.id AS token_id, t.workspace_id, t.actor_id, t.device_name,
            a.type, a.display_name, a.role, a.status, w.name AS workspace_name
     FROM access_tokens t
     JOIN actors a ON a.workspace_id = t.workspace_id AND a.id = t.actor_id
     JOIN workspaces w ON w.id = t.workspace_id
     WHERE t.token_hash = ? AND t.revoked_at IS NULL`,
  ).bind(tokenHash).first();
  if (!row) throw new RelayAuthError("Invalid or revoked Relay credential");
  if (row.status !== "active") throw new RelayAuthError("This Relay identity is not active", 403);

  const now = new Date().toISOString();
  context.waitUntil(
    env.DB.prepare("UPDATE access_tokens SET last_used_at = ? WHERE id = ?").bind(now, row.token_id).run(),
  );
  return {
    tokenID: row.token_id,
    workspaceID: row.workspace_id,
    workspaceName: row.workspace_name,
    actorID: row.actor_id,
    type: row.type,
    displayName: row.display_name,
    role: row.role,
    status: row.status,
    deviceName: row.device_name,
  };
}

function getMe(auth) {
  return json({
    workspace: { id: auth.workspaceID, name: auth.workspaceName },
    actor: { id: auth.actorID, type: auth.type, displayName: auth.displayName, role: auth.role, status: auth.status },
    device: { id: auth.tokenID, name: auth.deviceName },
  });
}

async function listActors(env, auth) {
  const { results } = await env.DB.prepare(
    "SELECT id, type, display_name, role, status FROM actors WHERE workspace_id = ? ORDER BY type DESC, display_name COLLATE NOCASE",
  ).bind(auth.workspaceID).all();
  return json(results.map(actorJSON));
}

async function listRooms(env, auth) {
  const { results } = await env.DB.prepare(
    `SELECT r.id, r.name, r.topic, r.is_archived, r.updated_at,
            COALESCE(rr.last_read_sequence, 0) AS last_read_sequence,
            COALESCE((SELECT MAX(m.sequence) FROM messages m WHERE m.room_id = r.id), 0) AS latest_sequence
     FROM rooms r
     LEFT JOIN read_receipts rr
       ON rr.workspace_id = r.workspace_id AND rr.room_id = r.id AND rr.actor_id = ?
     WHERE r.workspace_id = ? AND r.is_archived = 0
     ORDER BY r.updated_at DESC, r.name COLLATE NOCASE`,
  ).bind(auth.actorID, auth.workspaceID).all();
  return json(results.map(roomJSON));
}

async function createRoom(request, env, auth) {
  if (auth.type !== "human") throw new RelayAuthError("Only a human can create rooms", 403);
  const payload = await readJSON(request);
  const name = normalizeRoomName(payload.name);
  const topic = optionalText(payload.topic, "topic", 240);
  const now = new Date().toISOString();
  const id = crypto.randomUUID();
  try {
    await env.DB.prepare(
      "INSERT INTO rooms (id, workspace_id, name, topic, created_by, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
    ).bind(id, auth.workspaceID, name, topic, auth.actorID, now, now).run();
  } catch (error) {
    if (String(error?.message ?? "").includes("UNIQUE")) {
      throw new RelayInputError("A room with that name already exists", 409);
    }
    throw error;
  }
  return json(roomJSON({ id, name, topic, is_archived: 0, updated_at: now }), 201);
}

async function listMessages(url, env, auth, roomID) {
  await requireRoom(env, auth, roomID);
  const after = parseCursor(url.searchParams.get("after"));
  const rawBefore = url.searchParams.get("before");
  const before = rawBefore === null || rawBefore === "" ? null : parseCursor(rawBefore);
  if (after > 0 && before !== null) {
    throw new RelayInputError("after and before cannot be used together");
  }
  const limit = parseLimit(url.searchParams.get("limit"));
  const rows = await fetchMessageRows(env, auth.workspaceID, roomID, after, limit, before);
  return json(await hydrateMessages(env, rows));
}

async function postMessage(request, env, auth, roomID) {
  await requireRoom(env, auth, roomID);
  const payload = await readJSON(request);
  const body = requiredText(payload.body, "body", 12000);
  const format = payload.format === "plainText" ? "plainText" : "markdown";
  const idempotencyKey = requiredText(request.headers.get("idempotency-key"), "Idempotency-Key", 200);
  const replyToMessageID = payload.replyToMessageID ? requiredText(payload.replyToMessageID, "replyToMessageID", 80) : null;
  if (replyToMessageID) {
    const reply = await env.DB.prepare(
      "SELECT id FROM messages WHERE id = ? AND room_id = ? AND workspace_id = ?",
    ).bind(replyToMessageID, roomID, auth.workspaceID).first();
    if (!reply) throw new RelayInputError("Reply target was not found in this room");
  }

  const requestedMentions = uniqueStrings(payload.mentionedActorIDs).map(normalizeActorID);
  const mentionedActorIDs = await knownActors(env, auth.workspaceID, requestedMentions);
  const id = crypto.randomUUID();
  const now = new Date().toISOString();
  const insert = env.DB.prepare(
    `INSERT INTO messages
      (id, workspace_id, room_id, actor_id, body, format, reply_to_message_id, client_idempotency_key, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
     RETURNING sequence, id, workspace_id, room_id, actor_id, body, format, reply_to_message_id, created_at, edited_at`,
  ).bind(id, auth.workspaceID, roomID, auth.actorID, body, format, replyToMessageID, idempotencyKey, now);
  const statements = [insert];
  for (const mentionedActorID of mentionedActorIDs) {
    statements.push(
      env.DB.prepare(
        "INSERT INTO message_mentions (message_id, actor_id, workspace_id) VALUES (?, ?, ?)",
      ).bind(id, mentionedActorID, auth.workspaceID),
    );
  }
  statements.push(
    env.DB.prepare("UPDATE rooms SET updated_at = ? WHERE id = ? AND workspace_id = ?").bind(now, roomID, auth.workspaceID),
  );

  try {
    const results = await env.DB.batch(statements);
    const row = results[0]?.results?.[0];
    if (!row) throw new Error("D1 did not return the inserted message");
    return json(messageFromRow(row, mentionedActorIDs), 201);
  } catch (error) {
    if (!String(error?.message ?? "").includes("UNIQUE")) throw error;
    const existing = await env.DB.prepare(
      `SELECT sequence, id, workspace_id, room_id, actor_id, body, format, reply_to_message_id, created_at, edited_at
       FROM messages WHERE room_id = ? AND actor_id = ? AND client_idempotency_key = ?`,
    ).bind(roomID, auth.actorID, idempotencyKey).first();
    if (!existing) throw error;
    if (existing.body !== body || existing.reply_to_message_id !== replyToMessageID || existing.format !== format) {
      throw new RelayInputError("Idempotency-Key was already used for a different message", 409);
    }
    const mentions = await mentionsForMessage(env, existing.id);
    return json({ ...messageFromRow(existing, mentions), idempotentReplay: true });
  }
}

async function listMentions(url, env, auth) {
  const after = parseCursor(url.searchParams.get("after"));
  const limit = parseLimit(url.searchParams.get("limit"));
  const { results } = await env.DB.prepare(
    `SELECT m.sequence, m.id, m.workspace_id, m.room_id, m.actor_id, m.body, m.format,
            m.reply_to_message_id, m.created_at, m.edited_at
     FROM message_mentions mm
     JOIN messages m ON m.id = mm.message_id
     WHERE mm.workspace_id = ? AND mm.actor_id = ? AND m.sequence > ?
     ORDER BY m.sequence ASC LIMIT ?`,
  ).bind(auth.workspaceID, auth.actorID, after, limit).all();
  return json(await hydrateMessages(env, results));
}

async function searchMessages(url, env, auth) {
  const query = requiredText(url.searchParams.get("q"), "q", 120);
  const limit = parseLimit(url.searchParams.get("limit"), 50, 100);
  const { results } = await env.DB.prepare(
    `SELECT sequence, id, workspace_id, room_id, actor_id, body, format,
            reply_to_message_id, created_at, edited_at
     FROM messages
     WHERE workspace_id = ? AND body LIKE ? ESCAPE '\\'
     ORDER BY sequence DESC LIMIT ?`,
  ).bind(auth.workspaceID, `%${escapeLike(query)}%`, limit).all();
  return json(await hydrateMessages(env, results));
}

async function markRoomRead(request, env, auth, roomID) {
  await requireRoom(env, auth, roomID);
  const payload = await readJSON(request);
  const sequence = parseCursor(payload.sequence);
  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO read_receipts (workspace_id, actor_id, room_id, last_read_sequence, updated_at)
     VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(workspace_id, actor_id, room_id) DO UPDATE SET
       last_read_sequence = MAX(read_receipts.last_read_sequence, excluded.last_read_sequence),
       updated_at = excluded.updated_at`,
  ).bind(auth.workspaceID, auth.actorID, roomID, sequence, now).run();
  return json({ roomID, lastReadSequence: sequence, updatedAt: now });
}

async function updatePresence(request, env, auth) {
  const payload = await readJSON(request);
  const state = ["online", "away", "offline"].includes(payload.state) ? payload.state : "online";
  const deviceName = optionalText(payload.deviceName, "deviceName", 120) || auth.deviceName;
  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO presence (workspace_id, actor_id, device_name, state, last_seen_at)
     VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(workspace_id, actor_id, device_name) DO UPDATE SET
       state = excluded.state, last_seen_at = excluded.last_seen_at`,
  ).bind(auth.workspaceID, auth.actorID, deviceName, state, now).run();
  return json({ actorID: auth.actorID, deviceName, state, lastSeenAt: now });
}

async function sync(url, env, auth) {
  const after = parseCursor(url.searchParams.get("after"));
  const limit = parseLimit(url.searchParams.get("limit"), 300, 500);
  const [actorResult, roomResult, messageRows, receiptResult, presenceResult] = await Promise.all([
    env.DB.prepare(
      "SELECT id, type, display_name, role, status FROM actors WHERE workspace_id = ? ORDER BY display_name COLLATE NOCASE",
    ).bind(auth.workspaceID).all(),
    env.DB.prepare(
      "SELECT id, name, topic, is_archived, updated_at FROM rooms WHERE workspace_id = ? ORDER BY updated_at DESC",
    ).bind(auth.workspaceID).all(),
    fetchMessageRows(env, auth.workspaceID, null, after, limit),
    env.DB.prepare(
      "SELECT room_id, last_read_sequence, updated_at FROM read_receipts WHERE workspace_id = ? AND actor_id = ?",
    ).bind(auth.workspaceID, auth.actorID).all(),
    env.DB.prepare(
      "SELECT actor_id, device_name, state, last_seen_at FROM presence WHERE workspace_id = ? AND last_seen_at > ? ORDER BY last_seen_at DESC",
    ).bind(auth.workspaceID, new Date(Date.now() - 2 * 60 * 1000).toISOString()).all(),
  ]);
  const messages = await hydrateMessages(env, messageRows);
  return json({
    workspace: { id: auth.workspaceID, name: auth.workspaceName },
    currentActorID: auth.actorID,
    actors: actorResult.results.map(actorJSON),
    rooms: roomResult.results.map(roomJSON),
    messages,
    readReceipts: receiptResult.results.map((row) => ({
      roomID: row.room_id,
      lastReadSequence: Number(row.last_read_sequence),
      updatedAt: row.updated_at,
    })),
    presence: presenceResult.results.map((row) => ({
      actorID: row.actor_id,
      deviceName: row.device_name,
      state: row.state,
      lastSeenAt: row.last_seen_at,
    })),
    nextCursor: messages.at(-1)?.sequence ?? after,
    hasMore: messages.length === limit,
  });
}

async function listDevices(env, auth) {
  requireOwner(auth);
  const { results } = await env.DB.prepare(
    `SELECT t.id, t.actor_id, t.device_name, t.created_at, t.last_used_at, t.revoked_at,
            a.type, a.display_name
     FROM access_tokens t
     JOIN actors a ON a.workspace_id = t.workspace_id AND a.id = t.actor_id
     WHERE t.workspace_id = ? ORDER BY t.created_at DESC`,
  ).bind(auth.workspaceID).all();
  return json(results.map((row) => ({
    id: row.id,
    actorID: row.actor_id,
    actorType: row.type,
    displayName: row.display_name,
    deviceName: row.device_name,
    createdAt: row.created_at,
    lastUsedAt: row.last_used_at,
    revokedAt: row.revoked_at,
    isCurrent: row.id === auth.tokenID,
  })));
}

async function revokeDevice(env, auth, tokenID) {
  requireOwner(auth);
  if (tokenID === auth.tokenID) throw new RelayInputError("The current owner device cannot revoke itself", 409);
  const now = new Date().toISOString();
  const result = await env.DB.prepare(
    "UPDATE access_tokens SET revoked_at = ? WHERE id = ? AND workspace_id = ? AND revoked_at IS NULL",
  ).bind(now, tokenID, auth.workspaceID).run();
  if (!result.meta?.changes) throw new RelayInputError("Device was not found or was already revoked", 404);
  return json({ id: tokenID, revokedAt: now });
}

async function fetchMessageRows(env, workspaceID, roomID, after, limit, before = null) {
  if (roomID) {
    if (before !== null) {
      const { results } = await env.DB.prepare(
        `SELECT * FROM (
           SELECT sequence, id, workspace_id, room_id, actor_id, body, format,
                  reply_to_message_id, created_at, edited_at
           FROM messages WHERE workspace_id = ? AND room_id = ? AND sequence < ?
           ORDER BY sequence DESC LIMIT ?
         ) ORDER BY sequence ASC`,
      ).bind(workspaceID, roomID, before, limit).all();
      return results;
    }
    if (after > 0) {
      const { results } = await env.DB.prepare(
        `SELECT sequence, id, workspace_id, room_id, actor_id, body, format,
                reply_to_message_id, created_at, edited_at
         FROM messages WHERE workspace_id = ? AND room_id = ? AND sequence > ?
         ORDER BY sequence ASC LIMIT ?`,
      ).bind(workspaceID, roomID, after, limit).all();
      return results;
    }
    const { results } = await env.DB.prepare(
      `SELECT * FROM (
         SELECT sequence, id, workspace_id, room_id, actor_id, body, format,
                reply_to_message_id, created_at, edited_at
         FROM messages WHERE workspace_id = ? AND room_id = ?
         ORDER BY sequence DESC LIMIT ?
       ) ORDER BY sequence ASC`,
    ).bind(workspaceID, roomID, limit).all();
    return results;
  }
  const { results } = await env.DB.prepare(
    `SELECT sequence, id, workspace_id, room_id, actor_id, body, format,
            reply_to_message_id, created_at, edited_at
     FROM messages WHERE workspace_id = ? AND sequence > ?
     ORDER BY sequence ASC LIMIT ?`,
  ).bind(workspaceID, after, limit).all();
  return results;
}

async function hydrateMessages(env, rows) {
  if (!rows.length) return [];
  const ids = rows.map((row) => row.id);
  const placeholders = ids.map(() => "?").join(",");
  const { results } = await env.DB.prepare(
    `SELECT message_id, actor_id FROM message_mentions WHERE message_id IN (${placeholders}) ORDER BY actor_id`,
  ).bind(...ids).all();
  const mentions = new Map();
  for (const row of results) {
    const values = mentions.get(row.message_id) ?? [];
    values.push(row.actor_id);
    mentions.set(row.message_id, values);
  }
  return rows.map((row) => messageFromRow(row, mentions.get(row.id) ?? []));
}

async function mentionsForMessage(env, messageID) {
  const { results } = await env.DB.prepare(
    "SELECT actor_id FROM message_mentions WHERE message_id = ? ORDER BY actor_id",
  ).bind(messageID).all();
  return results.map((row) => row.actor_id);
}

async function knownActors(env, workspaceID, actorIDs) {
  if (!actorIDs.length) return [];
  const placeholders = actorIDs.map(() => "?").join(",");
  const { results } = await env.DB.prepare(
    `SELECT id FROM actors WHERE workspace_id = ? AND id IN (${placeholders}) AND status = 'active'`,
  ).bind(workspaceID, ...actorIDs).all();
  const known = new Set(results.map((row) => row.id));
  return actorIDs.filter((actorID) => known.has(actorID));
}

async function requireRoom(env, auth, roomID) {
  const room = await env.DB.prepare(
    "SELECT id FROM rooms WHERE id = ? AND workspace_id = ? AND is_archived = 0",
  ).bind(roomID, auth.workspaceID).first();
  if (!room) throw new RelayInputError("Room not found", 404);
  return room;
}

function requireOwner(auth) {
  if (auth.type !== "human" || auth.role !== "owner") {
    throw new RelayAuthError("Only the workspace owner can perform this action", 403);
  }
}

function actorJSON(row) {
  return {
    id: row.id,
    type: row.type,
    displayName: row.display_name,
    role: row.role,
    status: row.status,
  };
}

function roomJSON(row) {
  const lastReadSequence = Number(row.last_read_sequence ?? 0);
  const latestSequence = Number(row.latest_sequence ?? 0);
  return {
    id: row.id,
    name: row.name,
    title: row.name === "general" ? "General" : row.name,
    topic: row.topic ?? "",
    isArchived: Boolean(row.is_archived),
    updatedAt: row.updated_at,
    lastReadSequence,
    latestSequence,
    unreadCount: Math.max(0, latestSequence - lastReadSequence),
  };
}

function escapeLike(value) {
  return value.replace(/\\/g, "\\\\").replace(/%/g, "\\%").replace(/_/g, "\\_");
}

async function equalSecrets(expected, supplied) {
  if (!supplied) return false;
  const [expectedHash, suppliedHash] = await Promise.all([sha256(expected), sha256(supplied)]);
  let difference = 0;
  for (let index = 0; index < expectedHash.length; index += 1) {
    difference |= expectedHash.charCodeAt(index) ^ suppliedHash.charCodeAt(index);
  }
  return difference === 0;
}
