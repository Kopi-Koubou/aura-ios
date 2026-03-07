import { buildAuthHeaders, type AuthEnforcementMode, type AuthResolutionState } from "./request-guards.ts";
import type { RateLimitRow } from "./rate-limit.ts";

export interface RateLimitedDailyReading {
  is_premium: boolean;
  [key: string]: unknown;
}

interface RateLimitGateInput {
  rateLimit: RateLimitRow;
  rateLimitLookupFailed: boolean;
  existingReading: RateLimitedDailyReading | null;
  existingLookupFailed: boolean;
  requestedPremium: boolean;
  authMode: AuthEnforcementMode;
  authState: AuthResolutionState;
  usedAuthFallback: boolean;
}

export interface RateLimitGateResponse {
  status: 200 | 429 | 503;
  payload: Record<string, unknown>;
  headers: Record<string, string>;
}

export function resolveRateLimitGateResponse(input: RateLimitGateInput): RateLimitGateResponse | null {
  if (input.rateLimit.allowed) {
    return null;
  }

  const allowPremiumUpgrade =
    input.requestedPremium && Boolean(input.existingReading) && input.existingReading?.is_premium === false;

  if (input.existingReading && !allowPremiumUpgrade) {
    return {
      status: 200,
      payload: {
        cached: true,
        reason: input.rateLimit.reason,
        reading: input.existingReading,
        auth_mode: input.authMode,
        auth_context: input.authState,
        auth_fallback_identity: input.usedAuthFallback,
      },
      headers: buildAuthHeaders(input.authMode, input.authState, input.usedAuthFallback),
    };
  }

  if (allowPremiumUpgrade) {
    return null;
  }

  if (input.rateLimitLookupFailed || input.existingLookupFailed) {
    return {
      status: 503,
      payload: {
        error: "Rate limit enforcement is temporarily unavailable. Please retry shortly.",
        reason: input.rateLimit.reason,
        auth_mode: input.authMode,
        auth_context: input.authState,
      },
      headers: buildAuthHeaders(input.authMode, input.authState, input.usedAuthFallback),
    };
  }

  return {
    status: 429,
    payload: {
      error: "Reading already generated for this category today.",
      reason: input.rateLimit.reason,
      auth_mode: input.authMode,
      auth_context: input.authState,
    },
    headers: buildAuthHeaders(input.authMode, input.authState, input.usedAuthFallback),
  };
}
