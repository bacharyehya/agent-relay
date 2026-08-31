const actorIDPattern = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;
const roomNamePattern = /^[a-z0-9][a-z0-9-]{0,47}$/;

export function normalizeActorID(value) {
  const candidate = String(value ?? "").trim();
  if (!actorIDPattern.test(candidate)) {
    throw new RelayInputError("actorID must use 1-64 letters, numbers, dots, dashes, or underscores");
  }
  return candidate;
}

export function normalizeRoomName(value) {
  const candidate = String(value ?? "").trim().toLowerCase().replace(/\s+/g, "-");
  if (!roomNamePattern.test(candidate)) {
    throw new RelayInputError("room name must use 1-48 lowercase letters, numbers, or dashes");
  }
  return candidate;
}

export function requiredText(value, field, maxLength = 4000) {
  const candidate = String(value ?? "").trim();
  if (!candidate || candidate.length > maxLength) {
    throw new RelayInputError(`${field} must contain 1-${maxLength} characters`);
  }
  return candidate;
}

export function optionalText(value, field, maxLength = 4000) {
  if (value === undefined || value === null) return "";
  const candidate = String(value).trim();
  if (candidate.length > maxLength) {
    throw new RelayInputError(`${field} must contain at most ${maxLength} characters`);
  }
  return candidate;
}

export function parseCursor(value) {
  if (value === undefined || value === null || value === "") return 0;
  const cursor = Number(value);
  if (!Number.isSafeInteger(cursor) || cursor < 0) {
    throw new RelayInputError("cursor must be a non-negative integer");
  }
  return cursor;
}

export function parseLimit(value, fallback = 200, maximum = 500) {
  if (value === undefined || value === null || value === "") return fallback;
  const limit = Number(value);
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > maximum) {
    throw new RelayInputError(`limit must be between 1 and ${maximum}`);
  }
  return limit;
}

export function uniqueStrings(values, maximum = 32) {
  if (!Array.isArray(values)) return [];
  const result = [];
  const seen = new Set();
  for (const rawValue of values) {
    const value = String(rawValue ?? "").trim();
    if (!value || seen.has(value)) continue;
    seen.add(value);
    result.push(value);
    if (result.length >= maximum) break;
  }
  return result;
}

export async function sha256(value) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function randomToken(prefix = "relay") {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  const encoded = bytesToBase64URL(bytes);
  return `${prefix}_${encoded}`;
}

export function randomInviteCode() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = new Uint8Array(20);
  crypto.getRandomValues(bytes);
  let result = "";
  for (let index = 0; index < bytes.length; index += 1) {
    result += alphabet[bytes[index] % alphabet.length];
    if ([3, 7, 11, 15].includes(index)) result += "-";
  }
  return result;
}

export function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      ...headers,
    },
  });
}

export async function readJSON(request, maxBytes = 64 * 1024) {
  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (contentLength > maxBytes) throw new RelayInputError("request body is too large");
  let value;
  try {
    value = await request.json();
  } catch {
    throw new RelayInputError("request body must be valid JSON");
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new RelayInputError("request body must be a JSON object");
  }
  return value;
}

export function messageFromRow(row, mentions = []) {
  return {
    id: row.id,
    sequence: Number(row.sequence),
    roomID: row.room_id,
    threadID: row.room_id,
    actorID: row.actor_id,
    body: row.body,
    format: row.format,
    replyToMessageID: row.reply_to_message_id ?? null,
    mentionedActorIDs: mentions,
    createdAt: row.created_at,
    editedAt: row.edited_at ?? null,
  };
}

export class RelayInputError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.name = "RelayInputError";
    this.status = status;
  }
}

export class RelayAuthError extends Error {
  constructor(message = "Authentication required", status = 401) {
    super(message);
    this.name = "RelayAuthError";
    this.status = status;
  }
}

function bytesToBase64URL(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
