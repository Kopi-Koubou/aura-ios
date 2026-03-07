import test from "node:test";
import assert from "node:assert/strict";
import { evaluateUserIdentityPolicy } from "./auth-policy.ts";

const AUTH_USER_ID = "00000000-0000-4000-8000-000000000001";
const OTHER_USER_ID = "00000000-0000-4000-8000-000000000002";

test("audit mode allows user_id fallback when auth token is missing", () => {
  const result = evaluateUserIdentityPolicy({
    authMode: "audit",
    authState: "missing",
    authUserId: null,
    requestedUserId: AUTH_USER_ID,
  });

  assert.deepEqual(result, {
    ok: true,
    userId: AUTH_USER_ID,
    usedAuthFallback: true,
  });
});

test("enforce mode rejects requests without authenticated bearer token", () => {
  const result = evaluateUserIdentityPolicy({
    authMode: "enforce",
    authState: "missing",
    authUserId: null,
    requestedUserId: AUTH_USER_ID,
  });

  assert.deepEqual(result, {
    ok: false,
    status: 401,
    payload: {
      error: "Authorization bearer token is required for user-scoped requests",
      auth_mode: "enforce",
      auth_context: "missing",
    },
    usedAuthFallback: true,
  });
});

test("invalid requested user id is rejected with 400", () => {
  const result = evaluateUserIdentityPolicy({
    authMode: "audit",
    authState: "missing",
    authUserId: null,
    requestedUserId: "not-a-uuid",
  });

  assert.deepEqual(result, {
    ok: false,
    status: 400,
    payload: {
      error: "user_id is required and must be a UUID",
      auth_mode: "audit",
      auth_context: "missing",
    },
    usedAuthFallback: true,
  });
});

test("authenticated user mismatch is rejected with 403", () => {
  const result = evaluateUserIdentityPolicy({
    authMode: "audit",
    authState: "authenticated",
    authUserId: AUTH_USER_ID,
    requestedUserId: OTHER_USER_ID,
  });

  assert.deepEqual(result, {
    ok: false,
    status: 403,
    payload: {
      error: "user_id does not match authenticated user",
      auth_mode: "audit",
      auth_context: "authenticated",
    },
    usedAuthFallback: false,
  });
});

test("authenticated request without explicit user_id succeeds", () => {
  const result = evaluateUserIdentityPolicy({
    authMode: "enforce",
    authState: "authenticated",
    authUserId: AUTH_USER_ID,
    requestedUserId: undefined,
  });

  assert.deepEqual(result, {
    ok: true,
    userId: AUTH_USER_ID,
    usedAuthFallback: false,
  });
});

test("authenticated request treats user_id casing as equivalent", () => {
  const result = evaluateUserIdentityPolicy({
    authMode: "enforce",
    authState: "authenticated",
    authUserId: "7e7e2f55-3f2a-4b2e-a93f-3af6be27d241",
    requestedUserId: "7E7E2F55-3F2A-4B2E-A93F-3AF6BE27D241",
  });

  assert.deepEqual(result, {
    ok: true,
    userId: "7e7e2f55-3f2a-4b2e-a93f-3af6be27d241",
    usedAuthFallback: false,
  });
});

test("fallback user_id is canonicalized to lowercase UUID format", () => {
  const result = evaluateUserIdentityPolicy({
    authMode: "audit",
    authState: "missing",
    authUserId: null,
    requestedUserId: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE",
  });

  assert.deepEqual(result, {
    ok: true,
    userId: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
    usedAuthFallback: true,
  });
});
