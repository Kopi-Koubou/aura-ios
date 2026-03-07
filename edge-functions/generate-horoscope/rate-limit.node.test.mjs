import test from "node:test";
import assert from "node:assert/strict";
import { checkRateLimitWithFallback } from "./rate-limit.ts";

class FakeDailyReadingsQuery {
  constructor(result) {
    this.result = result;
    this.selectedColumns = null;
    this.filters = {};
    this.limitValue = null;
  }

  select(columns) {
    this.selectedColumns = columns;
    return this;
  }

  eq(column, value) {
    this.filters[column] = value;
    return this;
  }

  limit(count) {
    this.limitValue = count;
    return this;
  }

  async maybeSingle() {
    return this.result;
  }
}

function createFakeSupabase({ rpcResult, lookupResult }) {
  const state = {
    fromCalls: 0,
    rpcCall: null,
    lastLookup: null,
  };

  const client = {
    async rpc(name, rpcParams) {
      state.rpcCall = { name, params: rpcParams };
      return rpcResult;
    },
    from(table) {
      if (table !== "daily_readings") {
        throw new Error(`Unexpected table lookup in test: ${table}`);
      }

      state.fromCalls += 1;
      state.lastLookup = new FakeDailyReadingsQuery(lookupResult);
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
  const warnings = [];
  return {
    logger: {
      warn: (...args) => warnings.push(args),
    },
    warnings,
  };
}

const USER_ID = "00000000-0000-4000-8000-000000000001";
const DATE = "2026-03-05";
const CATEGORY = "Career";

test("checkRateLimitWithFallback uses RPC row when valid", async () => {
  const fakeSupabase = createFakeSupabase({
    rpcResult: {
      data: [{ allowed: false, existing_reading_id: "reading-1", reason: "already_generated_for_day" }],
      error: null,
    },
    lookupResult: { data: null, error: null },
  });
  const { logger, warnings } = createLogger();

  const result = await checkRateLimitWithFallback(fakeSupabase.client, USER_ID, CATEGORY, DATE, logger);

  assert.deepEqual(result, {
    allowed: false,
    existing_reading_id: "reading-1",
    reason: "already_generated_for_day",
  });
  assert.equal(fakeSupabase.fromCalls, 0);
  assert.equal(warnings.length, 0);
});

test("checkRateLimitWithFallback falls back to lookup on RPC error and blocks when existing row found", async () => {
  const fakeSupabase = createFakeSupabase({
    rpcResult: {
      data: null,
      error: { message: "function check_rate_limit does not exist" },
    },
    lookupResult: { data: { id: "existing-42" }, error: null },
  });
  const { logger } = createLogger();

  const result = await checkRateLimitWithFallback(fakeSupabase.client, USER_ID, CATEGORY, DATE, logger);

  assert.deepEqual(result, {
    allowed: false,
    existing_reading_id: "existing-42",
    reason: "already_generated_for_day",
  });
  assert.equal(fakeSupabase.fromCalls, 1);
  assert.equal(fakeSupabase.lastLookup?.selectedColumns, "id");
  assert.deepEqual(fakeSupabase.lastLookup?.filters, { user_id: USER_ID, category: CATEGORY, date: DATE });
  assert.equal(fakeSupabase.lastLookup?.limitValue, 1);
});

test("checkRateLimitWithFallback falls back when RPC returns no rows and allows generation when clear", async () => {
  const fakeSupabase = createFakeSupabase({
    rpcResult: { data: [], error: null },
    lookupResult: { data: null, error: null },
  });
  const { logger } = createLogger();

  const result = await checkRateLimitWithFallback(fakeSupabase.client, USER_ID, CATEGORY, DATE, logger);

  assert.deepEqual(result, {
    allowed: true,
    existing_reading_id: null,
    reason: "rate_limit_rpc_no_data_lookup_clear",
  });
  assert.equal(fakeSupabase.fromCalls, 1);
});

test("checkRateLimitWithFallback fails closed when lookup itself fails", async () => {
  const fakeSupabase = createFakeSupabase({
    rpcResult: { data: { allowed: "yes" }, error: null },
    lookupResult: { data: null, error: { message: "timeout talking to database" } },
  });
  const { logger } = createLogger();

  const result = await checkRateLimitWithFallback(fakeSupabase.client, USER_ID, CATEGORY, DATE, logger);

  assert.deepEqual(result, {
    allowed: false,
    existing_reading_id: null,
    reason: "rate_limit_rpc_no_data_lookup_failed",
  });
  assert.equal(fakeSupabase.fromCalls, 1);
});
