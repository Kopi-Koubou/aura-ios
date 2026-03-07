import { buildAuthHeaders, type AuthEnforcementMode, type AuthResolutionState } from "./request-guards.ts";

interface UserProfileRowLike {
  zodiac_sign?: string;
  mbti_type?: string;
}

interface UserProfileGateInput {
  userProfile: UserProfileRowLike | null;
  profileLookupFailed: boolean;
  zodiacSign: string | null;
  mbtiType: string | null;
  authMode: AuthEnforcementMode;
  authState: AuthResolutionState;
  usedAuthFallback: boolean;
}

interface UserProfileGateFailure {
  ok: false;
  status: 403 | 409 | 503;
  payload: {
    error: string;
    auth_mode: AuthEnforcementMode;
    auth_context: AuthResolutionState;
  };
  headers: Record<string, string>;
}

interface UserProfileGateSuccess {
  ok: true;
  zodiacSign: string;
  mbtiType: string;
}

export type UserProfileGateResult = UserProfileGateFailure | UserProfileGateSuccess;

export function resolveUserProfileGateResponse(input: UserProfileGateInput): UserProfileGateResult {
  if (input.profileLookupFailed) {
    return profileError(input, 503, "User profile lookup is temporarily unavailable. Please retry shortly.");
  }

  if (!input.userProfile) {
    return profileError(input, 403, "user_id is not provisioned");
  }

  if (!input.zodiacSign) {
    return profileError(input, 409, "user profile has invalid zodiac_sign");
  }

  if (!input.mbtiType) {
    return profileError(input, 409, "user profile has invalid mbti_type");
  }

  return {
    ok: true,
    zodiacSign: input.zodiacSign,
    mbtiType: input.mbtiType,
  };
}

function profileError(
  input: Pick<UserProfileGateInput, "authMode" | "authState" | "usedAuthFallback">,
  status: 403 | 409 | 503,
  error: string
): UserProfileGateFailure {
  return {
    ok: false,
    status,
    payload: {
      error,
      auth_mode: input.authMode,
      auth_context: input.authState,
    },
    headers: buildAuthHeaders(input.authMode, input.authState, input.usedAuthFallback),
  };
}
