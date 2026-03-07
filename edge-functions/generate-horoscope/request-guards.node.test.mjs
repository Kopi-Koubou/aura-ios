import test from "node:test";
import assert from "node:assert/strict";
import { buildAuthHeaders, coerceAuthEnforcementMode, normalizeDay } from "./request-guards.ts";

const NOW = new Date("2026-03-05T12:34:56.000Z");

test("normalizeDay defaults to current UTC day", () => {
  assert.equal(normalizeDay(undefined, NOW), "2026-03-05");
});

test("normalizeDay accepts same-day and +/-1 day values", () => {
  assert.equal(normalizeDay("2026-03-04", NOW), "2026-03-04");
  assert.equal(normalizeDay("2026-03-05", NOW), "2026-03-05");
  assert.equal(normalizeDay("2026-03-06", NOW), "2026-03-06");
});

test("normalizeDay rejects dates outside the allowed drift window", () => {
  assert.equal(normalizeDay("2026-03-03", NOW), null);
  assert.equal(normalizeDay("2026-03-07", NOW), null);
});

test("normalizeDay rejects malformed and impossible calendar dates", () => {
  assert.equal(normalizeDay("03-05-2026", NOW), null);
  assert.equal(normalizeDay("2026-13-01", NOW), null);
  assert.equal(normalizeDay("2026-02-30", new Date("2026-03-02T08:00:00.000Z")), null);
  assert.equal(normalizeDay("2025-02-29", new Date("2025-03-01T08:00:00.000Z")), null);
  assert.equal(normalizeDay("2024-02-29", new Date("2024-02-29T08:00:00.000Z")), "2024-02-29");
});

test("coerceAuthEnforcementMode normalizes valid values", () => {
  assert.equal(coerceAuthEnforcementMode("legacy"), "legacy");
  assert.equal(coerceAuthEnforcementMode(" AUDIT "), "audit");
  assert.equal(coerceAuthEnforcementMode("EnFoRcE"), "enforce");
});

test("coerceAuthEnforcementMode rejects unsupported values", () => {
  assert.equal(coerceAuthEnforcementMode(""), null);
  assert.equal(coerceAuthEnforcementMode("strict"), null);
  assert.equal(coerceAuthEnforcementMode(undefined), null);
  assert.equal(coerceAuthEnforcementMode(null), null);
});

test("buildAuthHeaders encodes auth context and fallback state", () => {
  assert.deepEqual(buildAuthHeaders("audit", "missing", true), {
    "x-aura-auth-mode": "audit",
    "x-aura-auth-context": "missing",
    "x-aura-auth-fallback": "1",
  });
  assert.deepEqual(buildAuthHeaders("enforce", "authenticated", false), {
    "x-aura-auth-mode": "enforce",
    "x-aura-auth-context": "authenticated",
    "x-aura-auth-fallback": "0",
  });
});
