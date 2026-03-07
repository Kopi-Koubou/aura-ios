export type SituationCategory = "Career" | "Love" | "Social" | "Health" | "Personal Growth";

export interface RateLimitRow {
  allowed: boolean;
  existing_reading_id: string | null;
  reason: string;
}

interface PostgrestErrorLike {
  code?: string;
  message?: string;
}

interface QueryResult {
  data: unknown;
  error: PostgrestErrorLike | null;
}

interface DailyReadingsLookupBuilder {
  select(columns: string): DailyReadingsLookupBuilder;
  eq(column: string, value: unknown): DailyReadingsLookupBuilder;
  limit(count: number): DailyReadingsLookupBuilder;
  maybeSingle(): Promise<QueryResult>;
}

export interface RateLimitSupabaseClient {
  rpc(name: string, params: Record<string, unknown>): Promise<QueryResult>;
  from(table: string): DailyReadingsLookupBuilder;
}

export interface LoggerLike {
  warn: (...args: unknown[]) => void;
}

const DEFAULT_LOGGER: LoggerLike = console;

export async function checkRateLimitWithFallback(
  supabase: RateLimitSupabaseClient,
  userId: string,
  category: SituationCategory,
  readingDate: string,
  logger: LoggerLike = DEFAULT_LOGGER
): Promise<RateLimitRow> {
  const { data, error } = await supabase.rpc("check_rate_limit", {
    p_user_id: userId,
    p_category: category,
    p_date: readingDate,
  });

  if (error) {
    logger.warn("check_rate_limit RPC failed, falling back to direct lookup:", error.message);
    return await checkRateLimitViaDirectLookup(
      supabase,
      userId,
      category,
      readingDate,
      "rate_limit_rpc_unavailable",
      logger
    );
  }

  const row = coerceRateLimitRow(data);
  if (!row) {
    logger.warn("check_rate_limit RPC returned no usable row, falling back to direct lookup");
    return await checkRateLimitViaDirectLookup(supabase, userId, category, readingDate, "rate_limit_rpc_no_data", logger);
  }

  return row;
}

async function checkRateLimitViaDirectLookup(
  supabase: RateLimitSupabaseClient,
  userId: string,
  category: SituationCategory,
  readingDate: string,
  fallbackReason: string,
  logger: LoggerLike
): Promise<RateLimitRow> {
  const { data, error } = await supabase
    .from("daily_readings")
    .select("id")
    .eq("user_id", userId)
    .eq("category", category)
    .eq("date", readingDate)
    .limit(1)
    .maybeSingle();

  if (error) {
    logger.warn("Direct rate-limit lookup failed; blocking generation to avoid policy bypass:", error.message);
    return {
      allowed: false,
      existing_reading_id: null,
      reason: `${fallbackReason}_lookup_failed`,
    };
  }

  const existingReadingId = coerceReadingId(data);
  if (!existingReadingId) {
    return {
      allowed: true,
      existing_reading_id: null,
      reason: `${fallbackReason}_lookup_clear`,
    };
  }

  return {
    allowed: false,
    existing_reading_id: existingReadingId,
    reason: "already_generated_for_day",
  };
}

function coerceRateLimitRow(data: unknown): RateLimitRow | null {
  const raw = Array.isArray(data) ? data[0] : data;
  if (!raw || typeof raw !== "object") {
    return null;
  }

  const candidate = raw as Partial<RateLimitRow>;
  if (typeof candidate.allowed !== "boolean") {
    return null;
  }

  const reason =
    typeof candidate.reason === "string" && candidate.reason.trim().length > 0
      ? candidate.reason
      : candidate.allowed
      ? "allowed"
      : "already_generated_for_day";

  return {
    allowed: candidate.allowed,
    existing_reading_id: typeof candidate.existing_reading_id === "string" ? candidate.existing_reading_id : null,
    reason,
  };
}

function coerceReadingId(data: unknown): string | null {
  if (!data || typeof data !== "object") {
    return null;
  }

  const value = (data as { id?: unknown }).id;
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}
