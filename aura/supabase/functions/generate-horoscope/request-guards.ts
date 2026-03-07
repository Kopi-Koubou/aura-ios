export type AuthEnforcementMode = "legacy" | "audit" | "enforce";
export type AuthResolutionState = "authenticated" | "missing" | "invalid";

const VALID_AUTH_MODES = new Set<AuthEnforcementMode>(["legacy", "audit", "enforce"]);
const DATE_ONLY_REGEX = /^\d{4}-\d{2}-\d{2}$/;
const DAY_IN_MILLISECONDS = 86_400_000;
const MAX_ALLOWED_DATE_DRIFT_DAYS = 1;

export function coerceAuthEnforcementMode(value?: string | null): AuthEnforcementMode | null {
  if (!value) {
    return null;
  }

  const normalized = value.trim().toLowerCase();
  if (!normalized) {
    return null;
  }

  return VALID_AUTH_MODES.has(normalized as AuthEnforcementMode)
    ? (normalized as AuthEnforcementMode)
    : null;
}

export function buildAuthHeaders(
  authMode: AuthEnforcementMode,
  authState: AuthResolutionState,
  usedAuthFallback: boolean
): Record<string, string> {
  return {
    "x-aura-auth-mode": authMode,
    "x-aura-auth-context": authState,
    "x-aura-auth-fallback": usedAuthFallback ? "1" : "0",
  };
}

export function normalizeDay(dateString?: string, now: Date = new Date()): string | null {
  if (!dateString) {
    return now.toISOString().slice(0, 10);
  }

  if (!DATE_ONLY_REGEX.test(dateString)) {
    return null;
  }

  const [year, month, day] = dateString.split("-").map(Number);
  if (!Number.isInteger(year) || !Number.isInteger(month) || !Number.isInteger(day)) {
    return null;
  }

  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (Number.isNaN(parsed.getTime())) {
    return null;
  }

  // Reject impossible dates that JS would otherwise normalize (for example 2026-02-30 -> 2026-03-02).
  const canonicalDate = parsed.toISOString().slice(0, 10);
  if (canonicalDate !== dateString) {
    return null;
  }

  const today = new Date(now);
  today.setUTCHours(0, 0, 0, 0);

  const dayDrift = Math.floor(Math.abs(parsed.getTime() - today.getTime()) / DAY_IN_MILLISECONDS);
  if (dayDrift > MAX_ALLOWED_DATE_DRIFT_DAYS) {
    return null;
  }

  return dateString;
}
