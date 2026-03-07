import {
  checkRateLimitWithFallback,
  type RateLimitSupabaseClient,
  type SituationCategory,
} from "./rate-limit.ts";

interface PostgrestErrorLike {
  message?: string;
}

interface QueryResult {
  data: unknown;
  error: PostgrestErrorLike | null;
}

interface CapturedRpcCall {
  name: string;
  params: Record<string, unknown>;
}

class FakeDailyReadingsQuery {
  selectedColumns: string | null = null;
  filters: Record<string, unknown> = {};
  limitValue: number | null = null;

  constructor(private readonly result: QueryResult) {}

  select(columns: string): FakeDailyReadingsQuery {
    this.selectedColumns = columns;
    return this;
  }

  eq(column: string, value: unknown): FakeDailyReadingsQuery {
    this.filters[column] = value;
    return this;
  }

  limit(count: number): FakeDailyReadingsQuery {
    this.limitValue = count;
    return this;
  }

  async maybeSingle(): Promise<QueryResult> {
    return this.result;
  }
}

function createFakeSupabase(params: {
  rpcResult: QueryResult;
  lookupResult: QueryResult;
}): {
  client: RateLimitSupabaseClient;
  fromCalls: number;
  rpcCall: CapturedRpcCall | null;
  lastLookup: FakeDailyReadingsQuery | null;
} {
  const state: {
    fromCalls: number;
    rpcCall: CapturedRpcCall | null;
    lastLookup: FakeDailyReadingsQuery | null;
  } = {
    fromCalls: 0,
    rpcCall: null,
    lastLookup: null,
  };

  const client: RateLimitSupabaseClient = {
    async rpc(name, rpcParams) {
      state.rpcCall = { name, params: rpcParams };
      return params.rpcResult;
    },
    from(table) {
      if (table !== "daily_readings") {
        throw new Error(`Unexpected table lookup in test: ${table}`);
      }
      state.fromCalls += 1;
      state.lastLookup = new FakeDailyReadingsQuery(params.lookupResult);
      return state.lastLookup;
    },
  };

  return {
    client,
    get fromCalls() {
      return state.fromCalls;
    },
    get rpcCall() {
      return state.rpcCall;
    },
    get lastLookup() {
      return state.lastLookup;
    },
  };
}

function createLogger() {
  const warnings: unknown[][] = [];
  return {
    logger: {
      warn: (...args: unknown[]) => warnings.push(args),
    },
    warnings,
  };
}

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

const USER_ID = "00000000-0000-4000-8000-000000000001";
const DATE = "2026-03-05";
const CATEGORY: SituationCategory = "Career";

Deno.test("checkRateLimitWithFallback uses RPC row when valid", async () => {
  const fakeSupabase = createFakeSupabase({
    rpcResult: {
      data: [{ allowed: false, existing_reading_id: "reading-1", reason: "already_generated_for_day" }],
      error: null,
    },
    lookupResult: { data: null, error: null },
  });
  const { logger, warnings } = createLogger();

  const result = await checkRateLimitWithFallback(fakeSupabase.client, USER_ID, CATEGORY, DATE, logger);

  assertEquals(
    result,
    {
      allowed: false,
      existing_reading_id: "reading-1",
      reason: "already_generated_for_day",
    },
    "Expected RPC row to be returned unchanged"
  );
  assert(fakeSupabase.fromCalls === 0, "Direct lookup should not run when RPC returns a valid row");
  assert(warnings.length === 0, "No warnings expected for successful RPC");
});

Deno.test("checkRateLimitWithFallback falls back to lookup on RPC error and blocks when existing row found", async () => {
  const fakeSupabase = createFakeSupabase({
    rpcResult: {
      data: null,
      error: { message: "function check_rate_limit does not exist" },
    },
    lookupResult: { data: { id: "existing-42" }, error: null },
  });
  const { logger } = createLogger();

  const result = await checkRateLimitWithFallback(fakeSupabase.client, USER_ID, CATEGORY, DATE, logger);

  assertEquals(
    result,
    {
      allowed: false,
      existing_reading_id: "existing-42",
      reason: "already_generated_for_day",
    },
    "Existing row in direct lookup must enforce rate-limit"
  );
  assert(fakeSupabase.fromCalls === 1, "Expected one direct lookup after RPC error");
  assert(fakeSupabase.lastLookup?.selectedColumns === "id", "Direct lookup should request only id");
  assertEquals(
    fakeSupabase.lastLookup?.filters,
    { user_id: USER_ID, category: CATEGORY, date: DATE },
    "Direct lookup should filter by user/category/date"
  );
  assert(fakeSupabase.lastLookup?.limitValue === 1, "Direct lookup should limit to one row");
});

Deno.test("checkRateLimitWithFallback falls back when RPC returns no rows and allows generation when clear", async () => {
  const fakeSupabase = createFakeSupabase({
    rpcResult: { data: [], error: null },
    lookupResult: { data: null, error: null },
  });
  const { logger } = createLogger();

  const result = await checkRateLimitWithFallback(fakeSupabase.client, USER_ID, CATEGORY, DATE, logger);

  assertEquals(
    result,
    {
      allowed: true,
      existing_reading_id: null,
      reason: "rate_limit_rpc_no_data_lookup_clear",
    },
    "Empty RPC response should allow only after direct lookup confirms no existing reading"
  );
  assert(fakeSupabase.fromCalls === 1, "Expected one direct lookup when RPC has no usable row");
});

Deno.test("checkRateLimitWithFallback fails closed when lookup itself fails", async () => {
  const fakeSupabase = createFakeSupabase({
    rpcResult: { data: { allowed: "yes" }, error: null },
    lookupResult: { data: null, error: { message: "timeout talking to database" } },
  });
  const { logger } = createLogger();

  const result = await checkRateLimitWithFallback(fakeSupabase.client, USER_ID, CATEGORY, DATE, logger);

  assertEquals(
    result,
    {
      allowed: false,
      existing_reading_id: null,
      reason: "rate_limit_rpc_no_data_lookup_failed",
    },
    "Lookup failures should fail closed with an explicit degraded-mode reason"
  );
  assert(fakeSupabase.fromCalls === 1, "Expected one direct lookup attempt");
});
