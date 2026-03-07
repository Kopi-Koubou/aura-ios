import test from "node:test";
import assert from "node:assert/strict";
import {
  resolveSharedCacheDegradationReason,
  resolveSharedCacheReadDecision,
  resolveSharedCacheWriteDecision,
} from "./cache-policy.ts";

test("resolveSharedCacheReadDecision returns cache hit when shared content exists", () => {
  const result = resolveSharedCacheReadDecision({
    cachedContent: "cached-content",
    lookupFailed: false,
    lookupTemporarilyUnavailable: false,
  });

  assert.deepEqual(result, {
    shouldGenerate: false,
    cached: true,
    content: "cached-content",
    reason: "shared_content_cache_hit",
    cacheLookupFailed: false,
    cacheTemporarilyUnavailable: false,
  });
});

test("resolveSharedCacheReadDecision flags cache unavailable degradation on lookup miss", () => {
  const result = resolveSharedCacheReadDecision({
    cachedContent: null,
    lookupFailed: true,
    lookupTemporarilyUnavailable: true,
  });

  assert.deepEqual(result, {
    shouldGenerate: true,
    cached: false,
    content: null,
    reason: "shared_content_cache_unavailable",
    cacheLookupFailed: true,
    cacheTemporarilyUnavailable: true,
  });
});

test("resolveSharedCacheWriteDecision returns persisted content when cache write succeeds", () => {
  const result = resolveSharedCacheWriteDecision({
    generatedContent: "generated",
    persistedContent: "persisted",
    persistFailed: false,
    persistTemporarilyUnavailable: false,
    priorLookupFailed: false,
    priorLookupTemporarilyUnavailable: false,
  });

  assert.deepEqual(result, {
    content: "persisted",
    cached: false,
    reason: "generated_shared_content_cached",
    cacheLookupFailed: false,
    cachePersistFailed: false,
    cacheTemporarilyUnavailable: false,
  });
});

test("resolveSharedCacheWriteDecision falls back to generated content when cache is temporarily unavailable", () => {
  const result = resolveSharedCacheWriteDecision({
    generatedContent: "generated",
    persistedContent: null,
    persistFailed: true,
    persistTemporarilyUnavailable: true,
    priorLookupFailed: true,
    priorLookupTemporarilyUnavailable: true,
  });

  assert.deepEqual(result, {
    content: "generated",
    cached: false,
    reason: "generated_shared_content_cache_temporarily_unavailable",
    cacheLookupFailed: true,
    cachePersistFailed: true,
    cacheTemporarilyUnavailable: true,
  });
});

test("resolveSharedCacheDegradationReason prioritizes shared cache unavailability", () => {
  const result = resolveSharedCacheDegradationReason({
    cacheLookupFailed: true,
    cachePersistFailed: false,
    cacheTemporarilyUnavailable: true,
  });

  assert.equal(result, "shared_content_cache_unavailable");
});

test("resolveSharedCacheDegradationReason returns persist-failed reason for non-temporary failures", () => {
  const result = resolveSharedCacheDegradationReason({
    cacheLookupFailed: false,
    cachePersistFailed: true,
    cacheTemporarilyUnavailable: false,
  });

  assert.equal(result, "generated_shared_content_cache_persist_failed");
});

test("resolveSharedCacheDegradationReason returns temporary-unavailable reason when applicable", () => {
  const result = resolveSharedCacheDegradationReason({
    cacheLookupFailed: false,
    cachePersistFailed: true,
    cacheTemporarilyUnavailable: true,
  });

  assert.equal(result, "generated_shared_content_cache_temporarily_unavailable");
});

test("resolveSharedCacheDegradationReason returns null when cache path is healthy", () => {
  const result = resolveSharedCacheDegradationReason({
    cacheLookupFailed: false,
    cachePersistFailed: false,
    cacheTemporarilyUnavailable: false,
  });

  assert.equal(result, null);
});
