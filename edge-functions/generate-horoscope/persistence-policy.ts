import { buildAuthHeaders, type AuthEnforcementMode, type AuthResolutionState } from "./request-guards.ts";

interface PostgrestErrorLike {
  code?: string;
  message?: string;
}

interface PersistedReadingLike {
  [key: string]: unknown;
}

interface ReadingPersistenceInput {
  upsertError: PostgrestErrorLike | null;
  reading: PersistedReadingLike | null;
  servedFromSharedCache: boolean;
  authMode: AuthEnforcementMode;
  authState: AuthResolutionState;
  usedAuthFallback: boolean;
  persistenceTemporarilyUnavailable: boolean;
}

export interface ReadingPersistenceResponse {
  status: 200 | 500 | 503;
  payload: Record<string, unknown>;
  headers: Record<string, string>;
}

export function resolveReadingPersistenceResponse(input: ReadingPersistenceInput): ReadingPersistenceResponse {
  const headers = buildAuthHeaders(input.authMode, input.authState, input.usedAuthFallback);

  if (input.upsertError || !input.reading) {
    if (input.persistenceTemporarilyUnavailable) {
      return {
        status: 503,
        payload: {
          error: "Daily reading persistence is temporarily unavailable. Please retry shortly.",
          auth_mode: input.authMode,
          auth_context: input.authState,
        },
        headers,
      };
    }

    return {
      status: 500,
      payload: {
        error: "Failed to persist generated reading",
        auth_mode: input.authMode,
        auth_context: input.authState,
      },
      headers,
    };
  }

  return {
    status: 200,
    payload: {
      cached: input.servedFromSharedCache,
      reason: input.servedFromSharedCache ? "shared_content_cache_hit" : "generated",
      reading: input.reading,
      auth_mode: input.authMode,
      auth_context: input.authState,
      auth_fallback_identity: input.usedAuthFallback,
    },
    headers,
  };
}
