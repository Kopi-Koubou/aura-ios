import test from "node:test";
import assert from "node:assert/strict";
import { sanitizeContent } from "./content-sanitizer.ts";

function wordCount(content) {
  return content.trim().split(/\s+/).filter(Boolean).length;
}

test("sanitizeContent falls back when generated content is blank", () => {
  const result = sanitizeContent("   \n\t ", false);
  assert.equal(
    result,
    "Cosmic signals are subtle today. Focus on one meaningful action and let consistency build your momentum."
  );
});

test("sanitizeContent enforces free-tier word limit", () => {
  const longFreeContent = Array.from({ length: 200 }, (_, index) => `word${index + 1}`).join(" ");
  const result = sanitizeContent(longFreeContent, false);

  assert.equal(wordCount(result), 150);
});

test("sanitizeContent enforces premium-tier word limit", () => {
  const longPremiumContent = Array.from({ length: 420 }, (_, index) => `word${index + 1}`).join(" ");
  const result = sanitizeContent(longPremiumContent, true);

  assert.equal(wordCount(result), 350);
});

test("sanitizeContent enforces 5000-character ceiling even for a single oversized token", () => {
  const oversizedToken = "A".repeat(6500);
  const result = sanitizeContent(oversizedToken, true);

  assert.equal(result.length, 5000);
});

test("sanitizeContent trims to a word boundary when char cap is hit", () => {
  const oversizedWithSpaces = Array.from({ length: 150 }, (_, index) => `${index + 1}${"A".repeat(45)}`).join(" ");
  const result = sanitizeContent(oversizedWithSpaces, false);

  assert.ok(result.length <= 5000);
  assert.ok(!result.endsWith(" "));
  assert.ok(wordCount(result) <= 150);
});
