const FREE_WORD_LIMIT = 150;
const PREMIUM_WORD_LIMIT = 350;
const DAILY_READING_CHAR_LIMIT = 5000;
const SANITIZE_FALLBACK_CONTENT =
  "Cosmic signals are subtle today. Focus on one meaningful action and let consistency build your momentum.";

export function sanitizeContent(content: string, isPremium: boolean): string {
  const normalized = content.replace(/\s+/g, " ").trim();
  const candidate = normalized.length === 0 ? SANITIZE_FALLBACK_CONTENT : normalized;
  const wordLimit = isPremium ? PREMIUM_WORD_LIMIT : FREE_WORD_LIMIT;
  const wordBounded = truncateByWordLimit(candidate, wordLimit);
  return truncateByCharLimit(wordBounded, DAILY_READING_CHAR_LIMIT);
}

function truncateByWordLimit(content: string, wordLimit: number): string {
  const words = content.split(/\s+/);
  if (words.length <= wordLimit) {
    return content;
  }

  return words.slice(0, wordLimit).join(" ");
}

function truncateByCharLimit(content: string, charLimit: number): string {
  if (content.length <= charLimit) {
    return content;
  }

  const truncated = content.slice(0, charLimit);
  const lastWhitespace = truncated.lastIndexOf(" ");
  if (lastWhitespace > 0) {
    const wordBoundary = truncated.slice(0, lastWhitespace).trimEnd();
    if (wordBoundary.length > 0) {
      return wordBoundary;
    }
  }

  return truncated.trimEnd();
}
