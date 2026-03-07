export type SharedCacheResolutionReason =
  | "shared_content_cache_hit"
  | "shared_content_cache_miss"
  | "shared_content_cache_unavailable"
  | "generated_shared_content_cached"
  | "generated_shared_content_cache_persist_failed"
  | "generated_shared_content_cache_temporarily_unavailable";

export type SharedCacheDegradationReason =
  | "shared_content_cache_unavailable"
  | "generated_shared_content_cache_persist_failed"
  | "generated_shared_content_cache_temporarily_unavailable";

interface SharedCacheReadDecisionInput {
  cachedContent: string | null;
  lookupFailed: boolean;
  lookupTemporarilyUnavailable: boolean;
}

export interface SharedCacheReadDecision {
  shouldGenerate: boolean;
  cached: boolean;
  content: string | null;
  reason: "shared_content_cache_hit" | "shared_content_cache_miss" | "shared_content_cache_unavailable";
  cacheLookupFailed: boolean;
  cacheTemporarilyUnavailable: boolean;
}

interface SharedCacheWriteDecisionInput {
  generatedContent: string;
  persistedContent: string | null;
  persistFailed: boolean;
  persistTemporarilyUnavailable: boolean;
  priorLookupFailed: boolean;
  priorLookupTemporarilyUnavailable: boolean;
}

export interface SharedCacheWriteDecision {
  content: string;
  cached: false;
  reason:
    | "generated_shared_content_cached"
    | "generated_shared_content_cache_persist_failed"
    | "generated_shared_content_cache_temporarily_unavailable";
  cacheLookupFailed: boolean;
  cachePersistFailed: boolean;
  cacheTemporarilyUnavailable: boolean;
}

export function resolveSharedCacheReadDecision(input: SharedCacheReadDecisionInput): SharedCacheReadDecision {
  if (input.cachedContent !== null) {
    return {
      shouldGenerate: false,
      cached: true,
      content: input.cachedContent,
      reason: "shared_content_cache_hit",
      cacheLookupFailed: false,
      cacheTemporarilyUnavailable: false,
    };
  }

  const reason = input.lookupTemporarilyUnavailable ? "shared_content_cache_unavailable" : "shared_content_cache_miss";

  return {
    shouldGenerate: true,
    cached: false,
    content: null,
    reason,
    cacheLookupFailed: input.lookupFailed,
    cacheTemporarilyUnavailable: input.lookupTemporarilyUnavailable,
  };
}

export function resolveSharedCacheWriteDecision(input: SharedCacheWriteDecisionInput): SharedCacheWriteDecision {
  const cacheTemporarilyUnavailable = input.priorLookupTemporarilyUnavailable || input.persistTemporarilyUnavailable;
  const cachePersistFailed = input.persistFailed || input.persistedContent === null;

  if (cachePersistFailed) {
    return {
      content: input.generatedContent,
      cached: false,
      reason: cacheTemporarilyUnavailable
        ? "generated_shared_content_cache_temporarily_unavailable"
        : "generated_shared_content_cache_persist_failed",
      cacheLookupFailed: input.priorLookupFailed,
      cachePersistFailed: true,
      cacheTemporarilyUnavailable,
    };
  }

  return {
    content: input.persistedContent,
    cached: false,
    reason: "generated_shared_content_cached",
    cacheLookupFailed: input.priorLookupFailed,
    cachePersistFailed: false,
    cacheTemporarilyUnavailable,
  };
}

interface SharedCacheDegradationReasonInput {
  cacheLookupFailed: boolean;
  cachePersistFailed: boolean;
  cacheTemporarilyUnavailable: boolean;
}

export function resolveSharedCacheDegradationReason(
  input: SharedCacheDegradationReasonInput
): SharedCacheDegradationReason | null {
  if (input.cacheLookupFailed) {
    return "shared_content_cache_unavailable";
  }

  if (!input.cachePersistFailed) {
    return null;
  }

  return input.cacheTemporarilyUnavailable
    ? "generated_shared_content_cache_temporarily_unavailable"
    : "generated_shared_content_cache_persist_failed";
}
