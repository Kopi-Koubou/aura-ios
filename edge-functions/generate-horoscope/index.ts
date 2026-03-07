import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import OpenAI from "https://esm.sh/openai@4.79.2";
import { evaluateUserIdentityPolicy } from "./auth-policy.ts";
import {
  resolveSharedCacheDegradationReason,
  resolveSharedCacheReadDecision,
  resolveSharedCacheWriteDecision,
  type SharedCacheDegradationReason,
  type SharedCacheResolutionReason,
} from "./cache-policy.ts";
import { sanitizeContent } from "./content-sanitizer.ts";
import { buildDeterministicExtras } from "./deterministic-extras.ts";
import { resolveRateLimitGateResponse } from "./handler.ts";
import { resolveReadingPersistenceResponse } from "./persistence-policy.ts";
import { resolveUserProfileGateResponse } from "./profile-policy.ts";
import { checkRateLimitWithFallback } from "./rate-limit.ts";
import {
  buildAuthHeaders,
  coerceAuthEnforcementMode,
  normalizeDay,
  type AuthEnforcementMode,
  type AuthResolutionState,
} from "./request-guards.ts";

type SituationCategory = "Career" | "Love" | "Social" | "Health" | "Personal Growth";

interface GenerateHoroscopeRequest {
  user_id?: string;
  zodiac_sign?: string;
  mbti_type?: string;
  category?: SituationCategory;
  is_premium?: boolean;
  date?: string;
  warm_cache?: boolean;
}

interface AuthResolution {
  userId: string | null;
  state: AuthResolutionState;
}

interface DailyReadingRow {
  id: string;
  user_id: string;
  date: string;
  category: string;
  content: string;
  fortune_score: number;
  lucky_numbers: number[];
  power_colors: string[];
  is_premium: boolean;
  created_at: string;
}

interface ExistingReadingLookupResult {
  reading: DailyReadingRow | null;
  lookupFailed: boolean;
}

interface GeneratedReadingCacheRow {
  content: string;
}

interface SharedCacheLookupResult {
  content: string | null;
  lookupFailed: boolean;
  temporarilyUnavailable: boolean;
}

interface SharedCachePersistResult {
  content: string | null;
  persistFailed: boolean;
  temporarilyUnavailable: boolean;
}

interface SharedCacheEntryResult {
  content: string;
  cached: boolean;
  reason: SharedCacheResolutionReason;
  cacheDegradationReason: SharedCacheDegradationReason | null;
  cacheLookupFailed: boolean;
  cachePersistFailed: boolean;
  cacheTemporarilyUnavailable: boolean;
}

interface UserProfileRow {
  id: string;
  zodiac_sign: string;
  mbti_type: string;
}

interface UserProfileLookupResult {
  profile: UserProfileRow | null;
  lookupFailed: boolean;
}

interface SubscriptionRow {
  tier: string | null;
  is_active: boolean | null;
  expires_at: string | null;
}

interface AuthFallbackMetricRow {
  fallback_count: number;
}

interface SharedCacheDegradationMetricRow {
  degradation_count: number;
  temporarily_unavailable_count: number;
}

const GENERATED_CACHE_TABLE = "generated_reading_cache";
const AUTH_FALLBACK_AUDIT_RPC = "record_generate_horoscope_auth_fallback";
const SHARED_CACHE_DEGRADATION_AUDIT_RPC = "record_generate_horoscope_shared_cache_degradation";
const VALID_CATEGORIES = new Set<SituationCategory>([
  "Career",
  "Love",
  "Social",
  "Health",
  "Personal Growth",
]);
const VALID_ZODIAC_SIGNS = new Set([
  "Aries",
  "Taurus",
  "Gemini",
  "Cancer",
  "Leo",
  "Virgo",
  "Libra",
  "Scorpio",
  "Sagittarius",
  "Capricorn",
  "Aquarius",
  "Pisces",
]);
const VALID_MBTI_TYPES = new Set([
  "INTJ",
  "INTP",
  "ENTJ",
  "ENTP",
  "INFJ",
  "INFP",
  "ENFJ",
  "ENFP",
  "ISTJ",
  "ISFJ",
  "ESTJ",
  "ESFJ",
  "ISTP",
  "ISFP",
  "ESTP",
  "ESFP",
]);
const CACHE_WARM_SECRET_HEADER = "x-cache-warm-secret";
const AUTH_MODE_ENV_KEY = "GENERATE_HOROSCOPE_AUTH_MODE";
const DEFAULT_AUTH_MODE: AuthEnforcementMode = "audit";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": `Authorization, Content-Type, apikey, ${CACHE_WARM_SECRET_HEADER}`,
  "Access-Control-Expose-Headers": "x-aura-auth-mode, x-aura-auth-context, x-aura-auth-fallback",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: "Function is not configured" }, 500);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);

  try {
    const body = (await req.json()) as GenerateHoroscopeRequest;
    if (!body.category || !VALID_CATEGORIES.has(body.category)) {
      return jsonResponse({ error: "category is invalid" }, 400);
    }

    const readingDate = normalizeDay(body.date);
    if (!readingDate) {
      return jsonResponse({ error: "date must be today or within +/- 1 day" }, 400);
    }

    const category = body.category;
    const requestedPremium = Boolean(body.is_premium);

    if (body.warm_cache === true) {
      if (!isAuthorizedWarmCacheRequest(req)) {
        return jsonResponse(
          { error: `warm_cache requests require a valid ${CACHE_WARM_SECRET_HEADER} header` },
          401
        );
      }

      const zodiacSign = normalizeZodiacSign(body.zodiac_sign);
      if (!zodiacSign) {
        return jsonResponse({ error: "zodiac_sign is invalid for warm_cache request" }, 400);
      }

      const mbtiType = normalizeMbtiType(body.mbti_type);
      if (!mbtiType) {
        return jsonResponse({ error: "mbti_type is invalid for warm_cache request" }, 400);
      }

      const warmCacheResult = await generateOrLoadSharedCacheEntry(
        supabase,
        zodiacSign,
        mbtiType,
        category,
        requestedPremium,
        readingDate
      );

      return jsonResponse(
        {
          cached: warmCacheResult.cached,
          reason: warmCacheResult.cached ? "shared_content_cache_hit" : "generated",
          cache_reason: warmCacheResult.reason,
          cache_degraded: warmCacheResult.cacheLookupFailed || warmCacheResult.cachePersistFailed,
          cache_degradation_reason: warmCacheResult.cacheDegradationReason,
          cache_temporarily_unavailable: warmCacheResult.cacheTemporarilyUnavailable,
          warm_cache: true,
          cache_entry: {
            date: readingDate,
            zodiac_sign: zodiacSign,
            mbti_type: mbtiType,
            category,
            is_premium: requestedPremium,
          },
          content: warmCacheResult.content,
        },
        200
      );
    }

    const authMode = resolveAuthEnforcementMode();
    const authResolution = await resolveAuthUserId(req, supabase);
    const authUserId = authResolution.userId;
    const identityPolicy = evaluateUserIdentityPolicy({
      authMode,
      authState: authResolution.state,
      authUserId,
      requestedUserId: body.user_id,
    });
    if (!identityPolicy.ok) {
      return jsonResponse(
        identityPolicy.payload,
        identityPolicy.status,
        buildAuthHeaders(authMode, authResolution.state, identityPolicy.usedAuthFallback)
      );
    }
    const userId = identityPolicy.userId;
    const usedAuthFallback = identityPolicy.usedAuthFallback;

    if (usedAuthFallback) {
      await maybeRecordAuthFallbackAudit(supabase, authMode, {
        userId,
        category,
        readingDate,
        authState: authResolution.state,
      });
    }

    const userProfileLookup = await fetchUserProfile(supabase, userId);
    const userProfile = userProfileLookup.profile;
    const profileGate = resolveUserProfileGateResponse({
      userProfile,
      profileLookupFailed: userProfileLookup.lookupFailed,
      zodiacSign: userProfile ? normalizeZodiacSign(userProfile.zodiac_sign) : null,
      mbtiType: userProfile ? normalizeMbtiType(userProfile.mbti_type) : null,
      authMode,
      authState: authResolution.state,
      usedAuthFallback,
    });
    if (!profileGate.ok) {
      return jsonResponse(profileGate.payload, profileGate.status, profileGate.headers);
    }
    const zodiacSign = profileGate.zodiacSign;
    const mbtiType = profileGate.mbtiType;

    const hasPremiumEntitlement = await hasActivePremiumEntitlement(supabase, userId);
    const isPremium = requestedPremium && hasPremiumEntitlement;

    const rateLimit = await checkRateLimitWithFallback(supabase, userId, category, readingDate, console);
    const rateLimitLookupFailed = rateLimit.reason.endsWith("_lookup_failed");
    if (!rateLimit.allowed) {
      const existingLookup = await fetchExistingReading(
        supabase,
        rateLimit.existing_reading_id,
        userId,
        category,
        readingDate
      );
      const rateLimitResponse = resolveRateLimitGateResponse({
        rateLimit,
        rateLimitLookupFailed,
        existingReading: existingLookup.reading,
        existingLookupFailed: existingLookup.lookupFailed,
        requestedPremium: isPremium,
        authMode,
        authState: authResolution.state,
        usedAuthFallback,
      });

      if (rateLimitResponse) {
        return jsonResponse(rateLimitResponse.payload, rateLimitResponse.status, rateLimitResponse.headers);
      }
    }

    const generatedReading = await generateOrLoadSharedCacheEntry(
      supabase,
      zodiacSign,
      mbtiType,
      category,
      isPremium,
      readingDate
    );
    const servedFromSharedCache = generatedReading.cached;
    const content = generatedReading.content;
    const deterministic = buildDeterministicExtras(userId, zodiacSign, readingDate);
    const createdAt = new Date().toISOString();

    const { data: reading, error: upsertError } = await supabase
      .from("daily_readings")
      .upsert(
        {
          user_id: userId,
          date: readingDate,
          category,
          content,
          fortune_score: deterministic.fortuneScore,
          lucky_numbers: deterministic.luckyNumbers,
          power_colors: deterministic.powerColors,
          is_premium: isPremium,
          created_at: createdAt,
        },
        { onConflict: "user_id,date,category" }
      )
      .select("id,user_id,date,category,content,fortune_score,lucky_numbers,power_colors,is_premium,created_at")
      .single();

    if (upsertError) {
      console.error("Failed to upsert daily_readings:", upsertError);
    } else if (!reading) {
      console.error("daily_readings upsert returned no row");
    }

    const persistenceResponse = resolveReadingPersistenceResponse({
      upsertError,
      reading: (reading as DailyReadingRow | null) ?? null,
      servedFromSharedCache,
      authMode,
      authState: authResolution.state,
      usedAuthFallback,
      persistenceTemporarilyUnavailable: isMissingDatabaseObjectError(upsertError),
    });

    return jsonResponse(persistenceResponse.payload, persistenceResponse.status, persistenceResponse.headers);
  } catch (error) {
    console.error("generate-horoscope failed:", error);
    return jsonResponse({ error: "Failed to generate reading" }, 500);
  }
});

async function resolveAuthUserId(
  req: Request,
  supabase: ReturnType<typeof createClient>
): Promise<AuthResolution> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return { userId: null, state: "missing" };
  }

  if (!authHeader.startsWith("Bearer ")) {
    return { userId: null, state: "invalid" };
  }

  const token = authHeader.replace("Bearer ", "").trim();
  if (!token) {
    return { userId: null, state: "invalid" };
  }

  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data.user) {
    return { userId: null, state: "invalid" };
  }

  return { userId: data.user.id, state: "authenticated" };
}

function resolveAuthEnforcementMode(): AuthEnforcementMode {
  const rawMode = Deno.env.get(AUTH_MODE_ENV_KEY);
  const coercedMode = coerceAuthEnforcementMode(rawMode);
  if (!coercedMode) {
    const normalizedRawMode = rawMode?.trim();
    if (normalizedRawMode) {
      console.warn(
        `Unsupported ${AUTH_MODE_ENV_KEY} value "${normalizedRawMode}". Falling back to "${DEFAULT_AUTH_MODE}".`
      );
    }
    return DEFAULT_AUTH_MODE;
  }

  return coercedMode;
}

async function maybeRecordAuthFallbackAudit(
  supabase: ReturnType<typeof createClient>,
  authMode: AuthEnforcementMode,
  details: { userId: string; category: SituationCategory; readingDate: string; authState: AuthResolutionState }
): Promise<void> {
  if (authMode !== "audit") {
    return;
  }

  const userHash = fnv1a32(details.userId).toString(16).padStart(8, "0");
  console.warn(
    "generate-horoscope accepted unauthenticated user_id fallback",
    JSON.stringify({
      event: "auth_fallback_accepted",
      auth_mode: authMode,
      auth_context: details.authState,
      user_hash: userHash,
      category: details.category,
      date: details.readingDate,
    })
  );

  const { data, error } = await supabase.rpc(AUTH_FALLBACK_AUDIT_RPC, {
    p_date: details.readingDate,
    p_category: details.category,
    p_auth_context: details.authState,
  });

  if (error) {
    if (!isMissingDatabaseObjectError(error)) {
      console.warn("Failed to persist auth fallback audit metric:", error.message);
    }
    return;
  }

  const metric = Array.isArray(data)
    ? (data[0] as AuthFallbackMetricRow | undefined)
    : (data as AuthFallbackMetricRow | null);
  if (!metric || typeof metric.fallback_count !== "number") {
    return;
  }

  console.info(
    "generate-horoscope auth fallback audit metric updated",
    JSON.stringify({
      event: "auth_fallback_metric_updated",
      date: details.readingDate,
      category: details.category,
      auth_context: details.authState,
      fallback_count: metric.fallback_count,
    })
  );
}

async function maybeRecordSharedCacheDegradationAudit(
  supabase: ReturnType<typeof createClient>,
  details: {
    category: SituationCategory;
    readingDate: string;
    isPremium: boolean;
    degradationReason: SharedCacheDegradationReason;
    cacheLookupFailed: boolean;
    cachePersistFailed: boolean;
    cacheTemporarilyUnavailable: boolean;
  }
): Promise<void> {
  const { data, error } = await supabase.rpc(SHARED_CACHE_DEGRADATION_AUDIT_RPC, {
    p_date: details.readingDate,
    p_category: details.category,
    p_is_premium: details.isPremium,
    p_resolution_reason: details.degradationReason,
    p_lookup_failed: details.cacheLookupFailed,
    p_persist_failed: details.cachePersistFailed,
    p_temporarily_unavailable: details.cacheTemporarilyUnavailable,
  });

  if (error) {
    if (!isMissingDatabaseObjectError(error)) {
      console.warn("Failed to persist shared cache degradation metric:", error.message);
    }
    return;
  }

  const metric = Array.isArray(data)
    ? (data[0] as SharedCacheDegradationMetricRow | undefined)
    : (data as SharedCacheDegradationMetricRow | null);
  if (!metric || typeof metric.degradation_count !== "number") {
    return;
  }

  console.info(
    "generate-horoscope shared cache degradation metric updated",
    JSON.stringify({
      event: "shared_cache_degradation_metric_updated",
      date: details.readingDate,
      category: details.category,
      is_premium: details.isPremium,
      degradation_reason: details.degradationReason,
      degradation_count: metric.degradation_count,
      temporarily_unavailable_count:
        typeof metric.temporarily_unavailable_count === "number" ? metric.temporarily_unavailable_count : null,
    })
  );
}

async function fetchUserProfile(
  supabase: ReturnType<typeof createClient>,
  userId: string
): Promise<UserProfileLookupResult> {
  const { data, error } = await supabase
    .from("users")
    .select("id,zodiac_sign,mbti_type")
    .eq("id", userId)
    .maybeSingle();

  if (error) {
    console.warn("Failed to load user profile:", error.message);
    return {
      profile: null,
      lookupFailed: true,
    };
  }

  return {
    profile: (data as UserProfileRow | null) ?? null,
    lookupFailed: false,
  };
}

async function hasActivePremiumEntitlement(
  supabase: ReturnType<typeof createClient>,
  userId: string
): Promise<boolean> {
  const { data, error } = await supabase
    .from("subscriptions")
    .select("tier,is_active,expires_at")
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    if (!isMissingDatabaseObjectError(error)) {
      console.warn("Failed to resolve subscription tier:", error.message);
    }
    return false;
  }

  const subscription = data as SubscriptionRow | null;
  if (!subscription) {
    return false;
  }

  const tier = subscription.tier?.toLowerCase() ?? "free";
  if (tier !== "premium") {
    return false;
  }

  if (subscription.is_active === false) {
    return false;
  }

  if (!subscription.expires_at) {
    return true;
  }

  const expiresAtMs = Date.parse(subscription.expires_at);
  if (Number.isNaN(expiresAtMs)) {
    return false;
  }

  return expiresAtMs > Date.now();
}

async function fetchExistingReading(
  supabase: ReturnType<typeof createClient>,
  existingReadingId: string | null,
  userId: string,
  category: SituationCategory,
  readingDate: string
): Promise<ExistingReadingLookupResult> {
  if (existingReadingId) {
    const { data, error } = await supabase
      .from("daily_readings")
      .select("id,user_id,date,category,content,fortune_score,lucky_numbers,power_colors,is_premium,created_at")
      .eq("id", existingReadingId)
      .maybeSingle();

    if (!error && data) {
      return {
        reading: data as DailyReadingRow,
        lookupFailed: false,
      };
    }

    if (error) {
      console.warn("Failed to load existing reading by id:", error.message);
    }
  }

  const { data, error } = await supabase
    .from("daily_readings")
    .select("id,user_id,date,category,content,fortune_score,lucky_numbers,power_colors,is_premium,created_at")
    .eq("user_id", userId)
    .eq("category", category)
    .eq("date", readingDate)
    .maybeSingle();

  if (error) {
    console.warn("Failed to load existing reading by user/category/date:", error.message);
    return {
      reading: null,
      lookupFailed: true,
    };
  }

  if (!data) {
    return {
      reading: null,
      lookupFailed: false,
    };
  }

  return {
    reading: data as DailyReadingRow,
    lookupFailed: false,
  };
}

async function fetchSharedGeneratedContent(
  supabase: ReturnType<typeof createClient>,
  zodiacSign: string,
  mbtiType: string,
  category: SituationCategory,
  isPremium: boolean,
  readingDate: string
): Promise<SharedCacheLookupResult> {
  const { data, error } = await supabase
    .from(GENERATED_CACHE_TABLE)
    .select("content")
    .eq("date", readingDate)
    .eq("zodiac_sign", zodiacSign)
    .eq("mbti_type", mbtiType)
    .eq("category", category)
    .eq("is_premium", isPremium)
    .maybeSingle();

  if (error) {
    const temporarilyUnavailable = isMissingDatabaseObjectError(error);
    if (!temporarilyUnavailable) {
      console.warn("Failed to fetch generated cache row:", error.message);
    }
    return {
      content: null,
      lookupFailed: true,
      temporarilyUnavailable,
    };
  }

  return {
    content: (data as GeneratedReadingCacheRow | null)?.content ?? null,
    lookupFailed: false,
    temporarilyUnavailable: false,
  };
}

async function upsertSharedGeneratedContent(
  supabase: ReturnType<typeof createClient>,
  zodiacSign: string,
  mbtiType: string,
  category: SituationCategory,
  isPremium: boolean,
  readingDate: string,
  content: string
): Promise<SharedCachePersistResult> {
  const { data, error } = await supabase
    .from(GENERATED_CACHE_TABLE)
    .upsert(
      {
        date: readingDate,
        zodiac_sign: zodiacSign,
        mbti_type: mbtiType,
        category,
        is_premium: isPremium,
        content,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "date,zodiac_sign,mbti_type,category,is_premium" }
    )
    .select("content")
    .maybeSingle();

  if (error) {
    const temporarilyUnavailable = isMissingDatabaseObjectError(error);
    if (!temporarilyUnavailable) {
      console.warn("Failed to upsert generated cache row:", error.message);
    }
    return {
      content: null,
      persistFailed: true,
      temporarilyUnavailable,
    };
  }

  return {
    content: (data as GeneratedReadingCacheRow | null)?.content ?? null,
    persistFailed: false,
    temporarilyUnavailable: false,
  };
}

async function generateContent(
  zodiacSign: string,
  mbtiType: string,
  category: SituationCategory,
  isPremium: boolean
): Promise<string> {
  const fallback = fallbackContent(zodiacSign, mbtiType, category);
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    return fallback;
  }

  try {
    const openai = new OpenAI({ apiKey });
    const completion = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        {
          role: "system",
          content: "You are an empathetic astrologer for the Aura app. Keep responses grounded, specific, and actionable.",
        },
        {
          role: "user",
          content: buildPrompt(zodiacSign, mbtiType, category, isPremium),
        },
      ],
      temperature: 0.8,
      max_tokens: isPremium ? 500 : 200,
    });

    const rawContent = completion.choices[0]?.message?.content;
    const content = typeof rawContent === "string" ? rawContent.trim() : "";
    return content.length > 0 ? content : fallback;
  } catch (error) {
    console.error("OpenAI generation failed:", error);
    return fallback;
  }
}

async function generateOrLoadSharedCacheEntry(
  supabase: ReturnType<typeof createClient>,
  zodiacSign: string,
  mbtiType: string,
  category: SituationCategory,
  isPremium: boolean,
  readingDate: string
): Promise<SharedCacheEntryResult> {
  const sharedCacheLookup = await fetchSharedGeneratedContent(
    supabase,
    zodiacSign,
    mbtiType,
    category,
    isPremium,
    readingDate
  );

  const readDecision = resolveSharedCacheReadDecision({
    cachedContent: sharedCacheLookup.content,
    lookupFailed: sharedCacheLookup.lookupFailed,
    lookupTemporarilyUnavailable: sharedCacheLookup.temporarilyUnavailable,
  });

  if (readDecision.cached && readDecision.content !== null) {
    return {
      content: sanitizeContent(readDecision.content, isPremium),
      cached: true,
      reason: readDecision.reason,
      cacheDegradationReason: null,
      cacheLookupFailed: readDecision.cacheLookupFailed,
      cachePersistFailed: false,
      cacheTemporarilyUnavailable: readDecision.cacheTemporarilyUnavailable,
    };
  }

  const generated = sanitizeContent(await generateContent(zodiacSign, mbtiType, category, isPremium), isPremium);
  const sharedCachePersist = await upsertSharedGeneratedContent(
    supabase,
    zodiacSign,
    mbtiType,
    category,
    isPremium,
    readingDate,
    generated
  );

  const writeDecision = resolveSharedCacheWriteDecision({
    generatedContent: generated,
    persistedContent: sharedCachePersist.content,
    persistFailed: sharedCachePersist.persistFailed,
    persistTemporarilyUnavailable: sharedCachePersist.temporarilyUnavailable,
    priorLookupFailed: readDecision.cacheLookupFailed,
    priorLookupTemporarilyUnavailable: readDecision.cacheTemporarilyUnavailable,
  });

  const degradationReason = resolveSharedCacheDegradationReason({
    cacheLookupFailed: writeDecision.cacheLookupFailed,
    cachePersistFailed: writeDecision.cachePersistFailed,
    cacheTemporarilyUnavailable: writeDecision.cacheTemporarilyUnavailable,
  });

  if (degradationReason) {
    console.warn(
      "generate-horoscope shared cache degraded",
      JSON.stringify({
        event: "shared_cache_degraded",
        reason: degradationReason,
        resolution_reason: writeDecision.reason,
        date: readingDate,
        category,
        zodiac_sign: zodiacSign,
        mbti_type: mbtiType,
        is_premium: isPremium,
        lookup_failed: writeDecision.cacheLookupFailed,
        persist_failed: writeDecision.cachePersistFailed,
        temporarily_unavailable: writeDecision.cacheTemporarilyUnavailable,
      })
    );

    await maybeRecordSharedCacheDegradationAudit(supabase, {
      category,
      readingDate,
      isPremium,
      degradationReason,
      cacheLookupFailed: writeDecision.cacheLookupFailed,
      cachePersistFailed: writeDecision.cachePersistFailed,
      cacheTemporarilyUnavailable: writeDecision.cacheTemporarilyUnavailable,
    });
  }

  return {
    content: sanitizeContent(writeDecision.content, isPremium),
    cached: writeDecision.cached,
    reason: writeDecision.reason,
    cacheDegradationReason: degradationReason,
    cacheLookupFailed: writeDecision.cacheLookupFailed,
    cachePersistFailed: writeDecision.cachePersistFailed,
    cacheTemporarilyUnavailable: writeDecision.cacheTemporarilyUnavailable,
  };
}

function buildPrompt(
  zodiacSign: string,
  mbtiType: string,
  category: SituationCategory,
  isPremium: boolean
): string {
  const wordCount = isPremium ? "250-350" : "100-150";
  return `Generate a daily horoscope reading for a ${mbtiType} ${zodiacSign} focused on ${category}.

Tone: Positive, empowering, actionable.
Length: ${wordCount} words.
Include:
- A concrete observation for today
- A practical next step
- A short encouraging close

Keep it personalized to both MBTI cognitive preferences and zodiac tendencies.`;
}

function fallbackContent(zodiacSign: string, mbtiType: string, category: SituationCategory): string {
  return `Today favors your ${category} focus. As a ${mbtiType} ${zodiacSign}, trust your pattern-recognition and take one concrete step before the day ends. Small momentum now will compound quickly.`;
}

function normalizeZodiacSign(value?: string): string | null {
  if (!value) {
    return null;
  }

  const trimmed = value.trim();
  if (!trimmed) {
    return null;
  }

  const normalized = `${trimmed.charAt(0).toUpperCase()}${trimmed.slice(1).toLowerCase()}`;
  return VALID_ZODIAC_SIGNS.has(normalized) ? normalized : null;
}

function normalizeMbtiType(value?: string): string | null {
  if (!value) {
    return null;
  }

  const normalized = value.trim().toUpperCase();
  if (!normalized) {
    return null;
  }

  return VALID_MBTI_TYPES.has(normalized) ? normalized : null;
}

function isMissingDatabaseObjectError(error: { code?: string; message?: string } | null): boolean {
  if (!error) {
    return false;
  }

  if (error.code === "42P01" || error.code === "42883") {
    return true;
  }

  const message = (error.message ?? "").toLowerCase();
  return message.includes("does not exist");
}

function isAuthorizedWarmCacheRequest(req: Request): boolean {
  const expectedSecret = Deno.env.get("CACHE_WARM_SECRET")?.trim();
  if (!expectedSecret) {
    console.warn("warm_cache request denied because CACHE_WARM_SECRET is not configured");
    return false;
  }

  const providedSecret = req.headers.get(CACHE_WARM_SECRET_HEADER)?.trim();
  if (!providedSecret) {
    return false;
  }

  return providedSecret === expectedSecret;
}

function jsonResponse(payload: Record<string, unknown>, status: number, extraHeaders: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      ...extraHeaders,
      "Content-Type": "application/json",
    },
  });
}
