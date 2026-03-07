import test from "node:test";
import assert from "node:assert/strict";
import { resolveUserProfileGateResponse } from "./profile-policy.ts";

test("resolveUserProfileGateResponse rejects missing profile with 403 and auth headers", () => {
  const result = resolveUserProfileGateResponse({
    userProfile: null,
    profileLookupFailed: false,
    zodiacSign: null,
    mbtiType: null,
    authMode: "audit",
    authState: "missing",
    usedAuthFallback: true,
  });

  assert.deepEqual(result, {
    ok: false,
    status: 403,
    payload: {
      error: "user_id is not provisioned",
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

test("resolveUserProfileGateResponse fails closed with 503 when profile lookup is degraded", () => {
  const result = resolveUserProfileGateResponse({
    userProfile: null,
    profileLookupFailed: true,
    zodiacSign: null,
    mbtiType: null,
    authMode: "enforce",
    authState: "authenticated",
    usedAuthFallback: false,
  });

  assert.deepEqual(result, {
    ok: false,
    status: 503,
    payload: {
      error: "User profile lookup is temporarily unavailable. Please retry shortly.",
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

test("resolveUserProfileGateResponse rejects invalid zodiac with 409", () => {
  const result = resolveUserProfileGateResponse({
    userProfile: {
      zodiac_sign: "nope",
      mbti_type: "INTJ",
    },
    profileLookupFailed: false,
    zodiacSign: null,
    mbtiType: "INTJ",
    authMode: "enforce",
    authState: "authenticated",
    usedAuthFallback: false,
  });

  assert.deepEqual(result, {
    ok: false,
    status: 409,
    payload: {
      error: "user profile has invalid zodiac_sign",
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

test("resolveUserProfileGateResponse rejects invalid mbti with 409", () => {
  const result = resolveUserProfileGateResponse({
    userProfile: {
      zodiac_sign: "Aries",
      mbti_type: "XXXX",
    },
    profileLookupFailed: false,
    zodiacSign: "Aries",
    mbtiType: null,
    authMode: "audit",
    authState: "authenticated",
    usedAuthFallback: false,
  });

  assert.deepEqual(result, {
    ok: false,
    status: 409,
    payload: {
      error: "user profile has invalid mbti_type",
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

test("resolveUserProfileGateResponse returns normalized profile identifiers when valid", () => {
  const result = resolveUserProfileGateResponse({
    userProfile: {
      zodiac_sign: "Aries",
      mbti_type: "INTJ",
    },
    profileLookupFailed: false,
    zodiacSign: "Aries",
    mbtiType: "INTJ",
    authMode: "enforce",
    authState: "authenticated",
    usedAuthFallback: false,
  });

  assert.deepEqual(result, {
    ok: true,
    zodiacSign: "Aries",
    mbtiType: "INTJ",
  });
});
