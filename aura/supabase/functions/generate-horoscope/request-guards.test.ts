import { buildAuthHeaders, coerceAuthEnforcementMode, normalizeDay } from "./request-guards.ts";

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

const NOW = new Date("2026-03-05T12:34:56.000Z");

Deno.test("normalizeDay defaults to current UTC day", () => {
  assertEquals(normalizeDay(undefined, NOW), "2026-03-05", "Expected normalizeDay to default to current UTC day");
});

Deno.test("normalizeDay accepts same-day and +/-1 day values", () => {
  assertEquals(normalizeDay("2026-03-04", NOW), "2026-03-04", "Expected yesterday to be accepted");
  assertEquals(normalizeDay("2026-03-05", NOW), "2026-03-05", "Expected today to be accepted");
  assertEquals(normalizeDay("2026-03-06", NOW), "2026-03-06", "Expected tomorrow to be accepted");
});

Deno.test("normalizeDay rejects dates outside the allowed drift window", () => {
  assertEquals(normalizeDay("2026-03-03", NOW), null, "Expected dates older than one day to be rejected");
  assertEquals(normalizeDay("2026-03-07", NOW), null, "Expected dates newer than one day to be rejected");
});

Deno.test("normalizeDay rejects malformed and impossible calendar dates", () => {
  assertEquals(normalizeDay("03-05-2026", NOW), null, "Expected malformed format to be rejected");
  assertEquals(normalizeDay("2026-13-01", NOW), null, "Expected out-of-range month to be rejected");
  assertEquals(
    normalizeDay("2026-02-30", new Date("2026-03-02T08:00:00.000Z")),
    null,
    "Expected impossible calendar dates to be rejected"
  );
  assertEquals(
    normalizeDay("2025-02-29", new Date("2025-03-01T08:00:00.000Z")),
    null,
    "Expected invalid non-leap day to be rejected"
  );
  assertEquals(
    normalizeDay("2024-02-29", new Date("2024-02-29T08:00:00.000Z")),
    "2024-02-29",
    "Expected valid leap day to be accepted"
  );
});

Deno.test("coerceAuthEnforcementMode normalizes valid values", () => {
  assertEquals(coerceAuthEnforcementMode("legacy"), "legacy", "Expected legacy to remain unchanged");
  assertEquals(coerceAuthEnforcementMode(" AUDIT "), "audit", "Expected audit value to be normalized");
  assertEquals(coerceAuthEnforcementMode("EnFoRcE"), "enforce", "Expected enforce to be normalized");
});

Deno.test("coerceAuthEnforcementMode rejects unsupported values", () => {
  assertEquals(coerceAuthEnforcementMode(""), null, "Expected empty values to be rejected");
  assertEquals(coerceAuthEnforcementMode("strict"), null, "Expected unsupported values to be rejected");
  assertEquals(coerceAuthEnforcementMode(undefined), null, "Expected undefined to be rejected");
  assertEquals(coerceAuthEnforcementMode(null), null, "Expected null to be rejected");
});

Deno.test("buildAuthHeaders encodes auth context and fallback state", () => {
  assertEquals(
    buildAuthHeaders("audit", "missing", true),
    {
      "x-aura-auth-mode": "audit",
      "x-aura-auth-context": "missing",
      "x-aura-auth-fallback": "1",
    },
    "Expected fallback flag to be encoded as 1"
  );
  assertEquals(
    buildAuthHeaders("enforce", "authenticated", false),
    {
      "x-aura-auth-mode": "enforce",
      "x-aura-auth-context": "authenticated",
      "x-aura-auth-fallback": "0",
    },
    "Expected fallback flag to be encoded as 0"
  );
});
