import { buildDeterministicExtras } from "./deterministic-extras.ts";

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

Deno.test("buildDeterministicExtras returns expected canonical sequence", () => {
  const result = buildDeterministicExtras("7e7e2f55-3f2a-4b2e-a93f-3af6be27d241", "Aries", "2026-03-05");

  assertEquals(
    result,
    {
      fortuneScore: 87,
      luckyNumbers: [21, 44, 63, 93, 94],
      powerColors: ["Emerald", "Teal", "Gold"],
    },
    "Expected deterministic extras to match canonical seeded sequence"
  );
});

Deno.test("buildDeterministicExtras canonicalizes user and zodiac casing", () => {
  const mixedCase = buildDeterministicExtras("7e7e2f55-3f2a-4b2e-a93f-3af6be27d241", "Aries", "2026-03-05");
  const canonicalCase = buildDeterministicExtras("7E7E2F55-3F2A-4B2E-A93F-3AF6BE27D241", "aries", "2026-03-05");

  assertEquals(
    mixedCase,
    canonicalCase,
    "Expected canonicalization to produce the same deterministic extras regardless of input case"
  );
});
