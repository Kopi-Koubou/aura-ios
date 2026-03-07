import { resolveUserProfileGateResponse } from "./profile-policy.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) {
    throw new Error(message);
  }
}

function assertEquals(actual: unknown, expected: unknown, message: string): void {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  assert(actualJson === expectedJson, `${message}\nExpected: ${expectedJson}\nActual:   ${actualJson}`);
}

Deno.test("resolveUserProfileGateResponse rejects missing profile with 403 and auth headers", () => {
  const result = resolveUserProfileGateResponse({
    userProfile: null,
    profileLookupFailed: false,
    zodiacSign: null,
    mbtiType: null,
    authMode: "audit",
    authState: "missing",
    usedAuthFallback: true,
  });

  assertEquals(
    result,
    {
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
    },
    "Expected missing profile branch to return 403 with auth headers"
  );
});

Deno.test("resolveUserProfileGateResponse fails closed with 503 when profile lookup is degraded", () => {
  const result = resolveUserProfileGateResponse({
    userProfile: null,
    profileLookupFailed: true,
    zodiacSign: null,
    mbtiType: null,
    authMode: "enforce",
    authState: "authenticated",
    usedAuthFallback: false,
  });

  assertEquals(
    result,
    {
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
    },
    "Expected degraded profile lookup branch to return 503 with auth metadata"
  );
});

Deno.test("resolveUserProfileGateResponse rejects invalid zodiac with 409", () => {
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

  assertEquals(
    result,
    {
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
    },
    "Expected invalid zodiac branch to return 409 with auth metadata"
  );
});

Deno.test("resolveUserProfileGateResponse rejects invalid mbti with 409", () => {
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

  assertEquals(
    result,
    {
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
    },
    "Expected invalid mbti branch to return 409 with auth metadata"
  );
});

Deno.test("resolveUserProfileGateResponse returns normalized profile identifiers when valid", () => {
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

  assertEquals(
    result,
    {
      ok: true,
      zodiacSign: "Aries",
      mbtiType: "INTJ",
    },
    "Expected valid profile branch to succeed"
  );
});
