import assert from "node:assert/strict";

const baseURL = process.env.RELAY_TEST_URL ?? "http://127.0.0.1:8787";
const bootstrapKey = process.env.RELAY_TEST_BOOTSTRAP_KEY ?? "relay-local-integration-only";

async function request(path, { method = "GET", token, body, headers = {} } = {}) {
  const response = await fetch(`${baseURL}${path}`, {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(body ? { "content-type": "application/json" } : {}),
      ...headers,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(`${method} ${path} failed (${response.status}): ${JSON.stringify(payload)}`);
  }
  return { response, payload };
}

const health = await request("/health");
assert.equal(health.payload.status, "ok");

const bootstrap = await request("/v1/bootstrap", {
  method: "POST",
  headers: { "x-relay-bootstrap-key": bootstrapKey },
  body: {
    workspaceName: "Bash's Agents",
    actorID: "bash",
    displayName: "Bash",
    deviceName: "M1 integration test",
  },
});
const ownerToken = bootstrap.payload.token;
const generalRoomID = bootstrap.payload.room.id;
assert.equal(bootstrap.payload.actor.role, "owner");

const agentInvitation = await request("/v1/invitations", {
  method: "POST",
  token: ownerToken,
  body: { kind: "agent", actorID: "codex-integration", displayName: "Integration Agent" },
});
const agentEnrollment = await request("/v1/enroll", {
  method: "POST",
  body: { code: agentInvitation.payload.code, deviceName: "Test worker" },
});
const agentToken = agentEnrollment.payload.token;
assert.equal(agentEnrollment.payload.actor.id, "codex-integration");

const secondAgentInvitation = await request("/v1/invitations", {
  method: "POST",
  token: ownerToken,
  body: { kind: "agent", actorID: "codex-integration", displayName: "Integration Agent" },
});
const secondAgentEnrollment = await request("/v1/enroll", {
  method: "POST",
  body: { code: secondAgentInvitation.payload.code, deviceName: "Second test worker" },
});
assert.equal(secondAgentEnrollment.payload.actor.id, "codex-integration");
assert.notEqual(secondAgentEnrollment.payload.token, agentToken);

const idempotencyKey = crypto.randomUUID();
const ownerMessageRequest = {
  method: "POST",
  token: ownerToken,
  headers: { "idempotency-key": idempotencyKey },
  body: {
    body: "@codex-integration reply with the integration status.",
    mentionedActorIDs: ["codex-integration", "codex-integration", "unknown-agent"],
  },
};
const ownerMessage = await request(`/v1/rooms/${generalRoomID}/messages`, ownerMessageRequest);
const replayedMessage = await request(`/v1/rooms/${generalRoomID}/messages`, ownerMessageRequest);
assert.equal(replayedMessage.payload.id, ownerMessage.payload.id);
assert.equal(replayedMessage.payload.idempotentReplay, true);
assert.deepEqual(ownerMessage.payload.mentionedActorIDs, ["codex-integration"]);

const mentions = await request("/v1/mentions?after=0", { token: agentToken });
assert.equal(mentions.payload.length, 1);
assert.equal(mentions.payload[0].id, ownerMessage.payload.id);

const agentMessage = await request(`/v1/rooms/${generalRoomID}/messages`, {
  method: "POST",
  token: agentToken,
  headers: { "idempotency-key": crypto.randomUUID() },
  body: {
    body: "Integration status: ready.",
    replyToMessageID: ownerMessage.payload.id,
    mentionedActorIDs: ["bash"],
  },
});
assert.equal(agentMessage.payload.actorID, "codex-integration");

const latestMessagePage = await request(`/v1/rooms/${generalRoomID}/messages?limit=1`, { token: ownerToken });
assert.deepEqual(latestMessagePage.payload.map((message) => message.id), [agentMessage.payload.id]);
const previousMessagePage = await request(
  `/v1/rooms/${generalRoomID}/messages?limit=1&before=${agentMessage.payload.sequence}`,
  { token: ownerToken },
);
assert.deepEqual(previousMessagePage.payload.map((message) => message.id), [ownerMessage.payload.id]);

const sync = await request("/v1/sync?after=0", { token: ownerToken });
assert.equal(sync.payload.messages.length, 2);
assert.equal(sync.payload.messages[1].replyToMessageID, ownerMessage.payload.id);
assert.equal(sync.payload.hasMore, false);

const humanInvitation = await request("/v1/invitations", {
  method: "POST",
  token: ownerToken,
  body: { kind: "human-device" },
});
const humanEnrollment = await request("/v1/enroll", {
  method: "POST",
  body: { code: humanInvitation.payload.code, deviceName: "iPhone integration test" },
});
assert.equal(humanEnrollment.payload.actor.id, "bash");

const newRoom = await request("/v1/rooms", {
  method: "POST",
  token: ownerToken,
  body: { name: "Product Build", topic: "Build Agent Relay in public." },
});
assert.equal(newRoom.payload.name, "product-build");

await request(`/v1/rooms/${generalRoomID}/read`, {
  method: "POST",
  token: ownerToken,
  body: { sequence: agentMessage.payload.sequence },
});
await request("/v1/presence", {
  method: "POST",
  token: agentToken,
  body: { state: "online" },
});
const search = await request("/v1/search?q=integration%20status", { token: ownerToken });
assert.ok(search.payload.some((message) => message.id === agentMessage.payload.id));

const devices = await request("/v1/devices", { token: ownerToken });
assert.equal(devices.payload.length, 4);

console.log("Agent Relay local cloud integration passed: owner + repeat agent enrollment + pagination + iPhone device + room sync.");
