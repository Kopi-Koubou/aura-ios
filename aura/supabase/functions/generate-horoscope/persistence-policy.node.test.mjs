import test from "node:test";
import assert from "node:assert/strict";
import { resolveReadingPersistenceResponse } from "./persistence-policy.ts";

const READING = {
  id: "reading-1",
  user_id: "00000000-0000-4000-8000-000000000001",
  date: "2026-03-05",
  category: "Career",
  content: "Generated reading",
  fortune_score: 82,
  lucky_numbers: [5, 14, 29, 41, 77],
  power_colors: ["Gold", "Teal", "Crimson"],
  is_premium: false,
  created_at: "2026-03-05T00:00:00.000Z",
};

test("resolveReadingPersistenceResponse returns 200 payload when upsert succeeds", () => {
  const result = resolveReadingPersistenceResponse({
    upsertError: null,
    reading: READING,
    servedFromSharedCache: true,
    authMode: "audit",
    authState: "authenticated",
    usedAuthFallback: false,
    persistenceTemporarilyUnavailable: false,
  });

  assert.deepEqual(result, {
    status: 200,
    payload: {
      cached: true,
      reason: "shared_content_cache_hit",
      reading: READING,
      auth_mode: "audit",
      auth_context: "authenticated",
      auth_fallback_identity: false,
    },
    headers: {
      "x-aura-auth-mode": "audit",
      "x-aura-auth-context": "authenticated",
      "x-aura-auth-fallback": "0",
    },
  });
});

test("resolveReadingPersistenceResponse returns 500 when upsert fails", () => {
  const result = resolveReadingPersistenceResponse({
    upsertError: { message: "insert failed" },
    reading: null,
    servedFromSharedCache: false,
    authMode: "enforce",
    authState: "authenticated",
    usedAuthFallback: false,
    persistenceTemporarilyUnavailable: false,
  });

  assert.deepEqual(result, {
    status: 500,
    payload: {
      error: "Failed to persist generated reading",
      auth_mode: "enforce",
      auth_context: "authenticated",
    },
    headers: {
      "x-aura-auth-mode": "enforce",
      "x-aura-auth-context": "authenticated",
      "x-aura-auth-fallback": "0",
    },
  });
});

test("resolveReadingPersistenceResponse returns 503 when persistence is temporarily unavailable", () => {
  const result = resolveReadingPersistenceResponse({
    upsertError: { code: "42P01", message: "relation does not exist" },
    reading: null,
    servedFromSharedCache: false,
    authMode: "audit",
    authState: "missing",
    usedAuthFallback: true,
    persistenceTemporarilyUnavailable: true,
  });

  assert.deepEqual(result, {
    status: 503,
    payload: {
      error: "Daily reading persistence is temporarily unavailable. Please retry shortly.",
      auth_mode: "audit",
      auth_context: "missing",
    },
    headers: {
      "x-aura-auth-mode": "audit",
      "x-aura-auth-context": "missing",
      "x-aura-auth-fallback": "1",
    },
  });
});

test("resolveReadingPersistenceResponse returns 500 when no row is returned without explicit error", () => {
  const result = resolveReadingPersistenceResponse({
    upsertError: null,
    reading: null,
    servedFromSharedCache: false,
    authMode: "audit",
    authState: "authenticated",
    usedAuthFallback: false,
    persistenceTemporarilyUnavailable: false,
  });

  assert.deepEqual(result, {
    status: 500,
    payload: {
      error: "Failed to persist generated reading",
      auth_mode: "audit",
      auth_context: "authenticated",
    },
    headers: {
      "x-aura-auth-mode": "audit",
      "x-aura-auth-context": "authenticated",
      "x-aura-auth-fallback": "0",
    },
  });
});
