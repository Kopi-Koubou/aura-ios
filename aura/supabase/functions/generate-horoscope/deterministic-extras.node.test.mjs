import test from "node:test";
import assert from "node:assert/strict";
import { buildDeterministicExtras } from "./deterministic-extras.ts";

test("buildDeterministicExtras returns expected canonical sequence", () => {
  const result = buildDeterministicExtras("7e7e2f55-3f2a-4b2e-a93f-3af6be27d241", "Aries", "2026-03-05");

  assert.deepEqual(result, {
    fortuneScore: 87,
    luckyNumbers: [21, 44, 63, 93, 94],
    powerColors: ["Emerald", "Teal", "Gold"],
  });
});

test("buildDeterministicExtras canonicalizes user and zodiac casing", () => {
  const mixedCase = buildDeterministicExtras("7e7e2f55-3f2a-4b2e-a93f-3af6be27d241", "Aries", "2026-03-05");
  const canonicalCase = buildDeterministicExtras("7E7E2F55-3F2A-4B2E-A93F-3AF6BE27D241", "aries", "2026-03-05");

  assert.deepEqual(mixedCase, canonicalCase);
});
