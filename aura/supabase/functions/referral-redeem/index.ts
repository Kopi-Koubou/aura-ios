import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface ReferralRedeemRequest {
  referral_code: string;
}

interface ReferralRedeemResponse {
  success: boolean;
  message: string;
  premium_granted?: boolean;
  premium_days?: number;
}

const PREMIUM_REWARD_DAYS = 7; // Both referrer and new user get 7 days
const RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1 minute
const RATE_LIMIT_MAX_REQUESTS = 5;

// Simple in-memory rate limiting (per edge function instance)
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();

function isRateLimited(userId: string): boolean {
  const now = Date.now();
  const record = rateLimitMap.get(userId);

  if (!record || now > record.resetAt) {
    rateLimitMap.set(userId, { count: 1, resetAt: now + RATE_LIMIT_WINDOW_MS });
    return false;
  }

  if (record.count >= RATE_LIMIT_MAX_REQUESTS) {
    return true;
  }

  record.count++;
  return false;
}

serve(async (req: Request) => {
  // CORS headers for preflight
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
      },
    });
  }

  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  // Verify JWT from request
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return new Response(
      JSON.stringify({ success: false, message: "Unauthorized" }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  const token = authHeader.replace("Bearer ", "");
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(token);

  if (authError || !user) {
    return new Response(
      JSON.stringify({ success: false, message: "Unauthorized" }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  // Rate limiting
  if (isRateLimited(user.id)) {
    return new Response(
      JSON.stringify({
        success: false,
        message: "Too many requests. Please try again later.",
      }),
      { status: 429, headers: { "Content-Type": "application/json" } }
    );
  }

  try {
    const { referral_code }: ReferralRedeemRequest = await req.json();

    if (!referral_code || typeof referral_code !== "string") {
      return new Response(
        JSON.stringify({ success: false, message: "Invalid referral code" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const normalizedCode = referral_code.trim().toUpperCase();

    // Validate code format (8 alphanumeric chars)
    if (!/^[A-Z0-9]{6,10}$/.test(normalizedCode)) {
      return new Response(
        JSON.stringify({ success: false, message: "Invalid referral code format" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Check if user has already redeemed a referral code
    const { data: existingRedemption } = await supabase
      .from("referral_redemptions")
      .select("id")
      .eq("redeemed_by_user_id", user.id)
      .single();

    if (existingRedemption) {
      return new Response(
        JSON.stringify({
          success: false,
          message: "You have already redeemed a referral code",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Find the referral code
    const { data: referralCode, error: findError } = await supabase
      .from("referral_codes")
      .select("*")
      .eq("code", normalizedCode)
      .eq("is_active", true)
      .single();

    if (findError || !referralCode) {
      return new Response(
        JSON.stringify({
          success: false,
          message: "Referral code not found or expired",
        }),
        { status: 404, headers: { "Content-Type": "application/json" } }
      );
    }

    // Prevent self-referral
    if (referralCode.user_id === user.id) {
      return new Response(
        JSON.stringify({
          success: false,
          message: "You cannot use your own referral code",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Check if code has reached max uses (if applicable)
    if (
      referralCode.max_uses !== null &&
      referralCode.times_used >= referralCode.max_uses
    ) {
      return new Response(
        JSON.stringify({
          success: false,
          message: "This referral code has reached its maximum uses",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Check expiration
    if (referralCode.expires_at && new Date(referralCode.expires_at) < new Date()) {
      return new Response(
        JSON.stringify({
          success: false,
          message: "This referral code has expired",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Begin transaction-like operations
    const now = new Date();
    const premiumEndsAt = new Date(now.getTime() + PREMIUM_REWARD_DAYS * 24 * 60 * 60 * 1000);

    // 1. Record the redemption
    const { error: redemptionError } = await supabase
      .from("referral_redemptions")
      .insert({
        referral_code_id: referralCode.id,
        referrer_user_id: referralCode.user_id,
        redeemed_by_user_id: user.id,
        reward_days: PREMIUM_REWARD_DAYS,
      });

    if (redemptionError) {
      console.error("Redemption insert error:", redemptionError);
      throw new Error("Failed to record redemption");
    }

    // 2. Increment usage count
    const { error: updateCodeError } = await supabase
      .from("referral_codes")
      .update({ times_used: referralCode.times_used + 1 })
      .eq("id", referralCode.id);

    if (updateCodeError) {
      console.error("Update code error:", updateCodeError);
    }

    // 3. Grant premium to the new user (person redeeming)
    const { error: newUserPremiumError } = await supabase
      .from("subscriptions")
      .upsert(
        {
          user_id: user.id,
          tier: "premium",
          is_active: true,
          is_referral_reward: true,
          referral_premium_expires_at: premiumEndsAt.toISOString(),
          updated_at: now.toISOString(),
        },
        { onConflict: "user_id" }
      );

    if (newUserPremiumError) {
      console.error("New user premium error:", newUserPremiumError);
    }

    // 4. Grant/extend premium to the referrer
    const { data: referrerSub } = await supabase
      .from("subscriptions")
      .select("*")
      .eq("user_id", referralCode.user_id)
      .single();

    let referrerPremiumEndsAt: Date;
    if (referrerSub?.referral_premium_expires_at) {
      // Extend existing referral premium
      const existingExpiry = new Date(referrerSub.referral_premium_expires_at);
      const baseDate = existingExpiry > now ? existingExpiry : now;
      referrerPremiumEndsAt = new Date(
        baseDate.getTime() + PREMIUM_REWARD_DAYS * 24 * 60 * 60 * 1000
      );
    } else {
      referrerPremiumEndsAt = premiumEndsAt;
    }

    const { error: referrerPremiumError } = await supabase
      .from("subscriptions")
      .upsert(
        {
          user_id: referralCode.user_id,
          tier: "premium",
          is_active: true,
          is_referral_reward: true,
          referral_premium_expires_at: referrerPremiumEndsAt.toISOString(),
          updated_at: now.toISOString(),
        },
        { onConflict: "user_id" }
      );

    if (referrerPremiumError) {
      console.error("Referrer premium error:", referrerPremiumError);
    }

    const response: ReferralRedeemResponse = {
      success: true,
      message: `Referral code redeemed! You and the referrer both get ${PREMIUM_REWARD_DAYS} days of premium.`,
      premium_granted: true,
      premium_days: PREMIUM_REWARD_DAYS,
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
    });
  } catch (error) {
    console.error("Referral redeem error:", error);
    return new Response(
      JSON.stringify({
        success: false,
        message: "An error occurred while redeeming the referral code",
      }),
      {
        status: 500,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      }
    );
  }
});
