import test from "node:test";
import assert from "node:assert/strict";
import { resolveRateLimitGateResponse } from "./handler.ts";

const READING = {
  id: "reading-1",
  user_id: "00000000-0000-4000-8000-000000000001",
  date: "2026-03-05",
  category: "Career",
  content: "Cached reading",
  fortune_score: 80,
  lucky_numbers: [3, 12, 21, 34, 55],
  power_colors: ["Gold", "Teal", "Crimson"],
  is_premium: false,
  created_at: "2026-03-05T00:00:00.000Z",
};

test("resolveRateLimitGateResponse returns cached reading response when reusable content exists", () => {
  const result = resolveRateLimitGateResponse({
    rateLimit: {
      allowed: false,
      existing_reading_id: "reading-1",
      reason: "already_generated_for_day",
    },
    rateLimitLookupFailed: false,
    existingReading: READING,
    existingLookupFailed: false,
    requestedPremium: false,
    authMode: "audit",
    authState: "authenticated",
    usedAuthFallback: false,
  });

  assert.deepEqual(result, {
    status: 200,
    payload: {
      cached: true,
      reason: "already_generated_for_day",
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

test("resolveRateLimitGateResponse allows premium upgrade when existing row is free", () => {
  const result = resolveRateLimitGateResponse({
    rateLimit: {
      allowed: false,
      existing_reading_id: "reading-1",
      reason: "already_generated_for_day",
    },
    rateLimitLookupFailed: false,
    existingReading: READING,
    existingLookupFailed: false,
    requestedPremium: true,
    authMode: "audit",
    authState: "authenticated",
    usedAuthFallback: false,
  });

  assert.equal(result, null);
});

test("resolveRateLimitGateResponse returns 503 with auth headers when rate-limit lookups are degraded", () => {
  const result = resolveRateLimitGateResponse({
    rateLimit: {
      allowed: false,
      existing_reading_id: null,
      reason: "rate_limit_rpc_no_data_lookup_failed",
    },
    rateLimitLookupFailed: true,
    existingReading: null,
    existingLookupFailed: false,
    requestedPremium: false,
    authMode: "enforce",
    authState: "authenticated",
    usedAuthFallback: false,
  });

  assert.deepEqual(result, {
    status: 503,
    payload: {
      error: "Rate limit enforcement is temporarily unavailable. Please retry shortly.",
      reason: "rate_limit_rpc_no_data_lookup_failed",
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

test("resolveRateLimitGateResponse returns 429 with auth headers when generation is already consumed", () => {
  const result = resolveRateLimitGateResponse({
    rateLimit: {
      allowed: false,
      existing_reading_id: null,
      reason: "already_generated_for_day",
    },
    rateLimitLookupFailed: false,
    existingReading: null,
    existingLookupFailed: false,
    requestedPremium: false,
    authMode: "audit",
    authState: "missing",
    usedAuthFallback: true,
  });

  assert.deepEqual(result, {
    status: 429,
    payload: {
      error: "Reading already generated for this category today.",
      reason: "already_generated_for_day",
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
