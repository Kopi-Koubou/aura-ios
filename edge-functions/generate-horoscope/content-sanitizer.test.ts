import { sanitizeContent } from "./content-sanitizer.ts";

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

function wordCount(content: string): number {
  return content.trim().split(/\s+/).filter(Boolean).length;
}

Deno.test("sanitizeContent falls back when generated content is blank", () => {
  const result = sanitizeContent("   \n\t ", false);
  assertEquals(
    result,
    "Cosmic signals are subtle today. Focus on one meaningful action and let consistency build your momentum.",
    "Expected blank output to fall back to deterministic baseline content"
  );
});

Deno.test("sanitizeContent enforces free-tier word limit", () => {
  const longFreeContent = Array.from({ length: 200 }, (_, index) => `word${index + 1}`).join(" ");
  const result = sanitizeContent(longFreeContent, false);
  assertEquals(wordCount(result), 150, "Expected free-tier output to be capped at 150 words");
});

Deno.test("sanitizeContent enforces premium-tier word limit", () => {
  const longPremiumContent = Array.from({ length: 420 }, (_, index) => `word${index + 1}`).join(" ");
  const result = sanitizeContent(longPremiumContent, true);
  assertEquals(wordCount(result), 350, "Expected premium output to be capped at 350 words");
});

Deno.test("sanitizeContent enforces 5000-character ceiling for oversized token output", () => {
  const oversizedToken = "A".repeat(6500);
  const result = sanitizeContent(oversizedToken, true);
  assertEquals(result.length, 5000, "Expected oversized token output to be hard-capped at 5000 characters");
});

Deno.test("sanitizeContent trims to a word boundary when char cap is hit", () => {
  const oversizedWithSpaces = Array.from({ length: 150 }, (_, index) => `${index + 1}${"A".repeat(45)}`).join(" ");
  const result = sanitizeContent(oversizedWithSpaces, false);
  assert(result.length <= 5000, "Expected sanitized output to stay within 5000 characters");
  assert(!result.endsWith(" "), "Expected sanitized output to avoid trailing whitespace");
  assert(wordCount(result) <= 150, "Expected sanitized output to stay within free-tier word limit");
});
