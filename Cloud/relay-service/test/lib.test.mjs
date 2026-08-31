import test from "node:test";
import assert from "node:assert/strict";
import {
  RelayInputError,
  normalizeActorID,
  normalizeRoomName,
  parseCursor,
  parseLimit,
  randomInviteCode,
  randomToken,
  requiredText,
  sha256,
  uniqueStrings,
} from "../src/lib.js";

test("actor IDs are exact and do not accept whitespace or path characters", () => {
  assert.equal(normalizeActorID("codex-m5"), "codex-m5");
  assert.equal(normalizeActorID(" codex.main "), "codex.main");
  assert.throws(() => normalizeActorID("codex main"), RelayInputError);
  assert.throws(() => normalizeActorID("../codex"), RelayInputError);
});

test("room names normalize to predictable Slack-style slugs", () => {
  assert.equal(normalizeRoomName("Product Build"), "product-build");
  assert.throws(() => normalizeRoomName("Product / Build"), RelayInputError);
});

test("cursor and limit parsing reject unsafe values", () => {
  assert.equal(parseCursor(undefined), 0);
  assert.equal(parseCursor("42"), 42);
  assert.throws(() => parseCursor("-1"), RelayInputError);
  assert.equal(parseLimit(undefined), 200);
  assert.throws(() => parseLimit("501"), RelayInputError);
});

test("message text and mention normalization are bounded", () => {
  assert.equal(requiredText(" hello ", "body", 10), "hello");
  assert.throws(() => requiredText("", "body"), RelayInputError);
  assert.deepEqual(uniqueStrings(["codex-main", "codex-main", "", "codex-m5"]), ["codex-main", "codex-m5"]);
});

test("tokens and invite codes have stable non-secret formats", async () => {
  const token = randomToken("relay_test");
  const secondToken = randomToken("relay_test");
  assert.match(token, /^relay_test_[A-Za-z0-9_-]{40,}$/);
  assert.notEqual(token, secondToken);
  assert.match(randomInviteCode(), /^[A-Z2-9]{4}(?:-[A-Z2-9]{4}){4}$/);
  assert.equal((await sha256("agent-relay")).length, 64);
});
