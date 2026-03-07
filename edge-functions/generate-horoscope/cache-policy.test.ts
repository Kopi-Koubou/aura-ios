import {
  resolveSharedCacheDegradationReason,
  resolveSharedCacheReadDecision,
  resolveSharedCacheWriteDecision,
} from "./cache-policy.ts";

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

Deno.test("resolveSharedCacheReadDecision returns cache hit when shared content exists", () => {
  const result = resolveSharedCacheReadDecision({
    cachedContent: "cached-content",
    lookupFailed: false,
    lookupTemporarilyUnavailable: false,
  });

  assertEquals(
    result,
    {
      shouldGenerate: false,
      cached: true,
      content: "cached-content",
      reason: "shared_content_cache_hit",
      cacheLookupFailed: false,
      cacheTemporarilyUnavailable: false,
    },
    "Expected cache hit response to bypass generation"
  );
});

Deno.test("resolveSharedCacheReadDecision flags cache unavailable degradation on lookup miss", () => {
  const result = resolveSharedCacheReadDecision({
    cachedContent: null,
    lookupFailed: true,
    lookupTemporarilyUnavailable: true,
  });

  assertEquals(
    result,
    {
      shouldGenerate: true,
      cached: false,
      content: null,
      reason: "shared_content_cache_unavailable",
      cacheLookupFailed: true,
      cacheTemporarilyUnavailable: true,
    },
    "Expected missing cache table branch to degrade but continue generation"
  );
});

Deno.test("resolveSharedCacheWriteDecision returns persisted content when cache write succeeds", () => {
  const result = resolveSharedCacheWriteDecision({
    generatedContent: "generated",
    persistedContent: "persisted",
    persistFailed: false,
    persistTemporarilyUnavailable: false,
    priorLookupFailed: false,
    priorLookupTemporarilyUnavailable: false,
  });

  assertEquals(
    result,
    {
      content: "persisted",
      cached: false,
      reason: "generated_shared_content_cached",
      cacheLookupFailed: false,
      cachePersistFailed: false,
      cacheTemporarilyUnavailable: false,
    },
    "Expected cache write success to return persisted content"
  );
});

Deno.test("resolveSharedCacheWriteDecision falls back to generated content when cache is temporarily unavailable", () => {
  const result = resolveSharedCacheWriteDecision({
    generatedContent: "generated",
    persistedContent: null,
    persistFailed: true,
    persistTemporarilyUnavailable: true,
    priorLookupFailed: true,
    priorLookupTemporarilyUnavailable: true,
  });

  assertEquals(
    result,
    {
      content: "generated",
      cached: false,
      reason: "generated_shared_content_cache_temporarily_unavailable",
      cacheLookupFailed: true,
      cachePersistFailed: true,
      cacheTemporarilyUnavailable: true,
    },
    "Expected missing cache table branch to serve generated content with explicit degradation signal"
  );
});

Deno.test("resolveSharedCacheDegradationReason prioritizes shared cache unavailability", () => {
  const result = resolveSharedCacheDegradationReason({
    cacheLookupFailed: true,
    cachePersistFailed: false,
    cacheTemporarilyUnavailable: true,
  });

  assertEquals(
    result,
    "shared_content_cache_unavailable",
    "Expected lookup degradation to map to shared cache unavailable reason"
  );
});

Deno.test("resolveSharedCacheDegradationReason returns persist-failed reason for non-temporary failures", () => {
  const result = resolveSharedCacheDegradationReason({
    cacheLookupFailed: false,
    cachePersistFailed: true,
    cacheTemporarilyUnavailable: false,
  });

  assertEquals(
    result,
    "generated_shared_content_cache_persist_failed",
    "Expected persist failure without temporary unavailability to map to persist_failed reason"
  );
});

Deno.test("resolveSharedCacheDegradationReason returns temporary-unavailable reason when applicable", () => {
  const result = resolveSharedCacheDegradationReason({
    cacheLookupFailed: false,
    cachePersistFailed: true,
    cacheTemporarilyUnavailable: true,
  });

  assertEquals(
    result,
    "generated_shared_content_cache_temporarily_unavailable",
    "Expected temporary unavailability to map to dedicated degradation reason"
  );
});

Deno.test("resolveSharedCacheDegradationReason returns null when cache path is healthy", () => {
  const result = resolveSharedCacheDegradationReason({
    cacheLookupFailed: false,
    cachePersistFailed: false,
    cacheTemporarilyUnavailable: false,
  });

  assertEquals(result, null, "Expected healthy cache path to return no degradation reason");
});
