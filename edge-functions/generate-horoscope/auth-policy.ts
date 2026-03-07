import { type AuthEnforcementMode, type AuthResolutionState } from "./request-guards.ts";

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

interface EvaluateUserIdentityPolicyInput {
  authMode: AuthEnforcementMode;
  authState: AuthResolutionState;
  authUserId: string | null;
  requestedUserId?: string | null;
}

interface AuthPolicyErrorPayload {
  error: string;
  auth_mode: AuthEnforcementMode;
  auth_context: AuthResolutionState;
}

export interface UserIdentityPolicySuccess {
  ok: true;
  userId: string;
  usedAuthFallback: boolean;
}

export interface UserIdentityPolicyFailure {
  ok: false;
  status: 400 | 401 | 403;
  payload: AuthPolicyErrorPayload;
  usedAuthFallback: boolean;
}

export type UserIdentityPolicyResult = UserIdentityPolicySuccess | UserIdentityPolicyFailure;

export function evaluateUserIdentityPolicy(
  input: EvaluateUserIdentityPolicyInput
): UserIdentityPolicyResult {
  const requestedUserIdRaw = input.requestedUserId?.trim() ?? null;
  const authUserId = normalizeUuid(input.authUserId);
  const requestedUserId = normalizeUuid(input.requestedUserId);
  const usedAuthFallback = !authUserId && Boolean(requestedUserIdRaw);

  if (!authUserId && input.authMode === "enforce") {
    return authError(
      input.authMode,
      input.authState,
      usedAuthFallback,
      401,
      "Authorization bearer token is required for user-scoped requests"
    );
  }

  const resolvedUserId = authUserId ?? requestedUserId;
  if (!resolvedUserId) {
    return authError(input.authMode, input.authState, usedAuthFallback, 400, "user_id is required and must be a UUID");
  }

  if (authUserId && requestedUserId && requestedUserId !== authUserId) {
    return authError(input.authMode, input.authState, usedAuthFallback, 403, "user_id does not match authenticated user");
  }

  return {
    ok: true,
    userId: resolvedUserId,
    usedAuthFallback,
  };
}

function normalizeUuid(value?: string | null): string | null {
  const normalized = value?.trim();
  if (!normalized || !UUID_REGEX.test(normalized)) {
    return null;
  }

  return normalized.toLowerCase();
}

function authError(
  authMode: AuthEnforcementMode,
  authState: AuthResolutionState,
  usedAuthFallback: boolean,
  status: 400 | 401 | 403,
  error: string
): UserIdentityPolicyFailure {
  return {
    ok: false,
    status,
    payload: {
      error,
      auth_mode: authMode,
      auth_context: authState,
    },
    usedAuthFallback,
  };
}
