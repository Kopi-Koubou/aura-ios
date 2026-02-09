import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type SharePlatform =
  | "imessage"
  | "instagram"
  | "instagram_story"
  | "twitter"
  | "facebook"
  | "whatsapp"
  | "telegram"
  | "snapchat"
  | "tiktok"
  | "email"
  | "copy_link"
  | "other";

type ContentType = "reading" | "mbti_result" | "weekly_forecast" | "compatibility" | "profile";

interface ShareEventRequest {
  content_type: ContentType;
  content_id?: string; // reading_id, result_id, etc.
  share_platform: SharePlatform;
  utm_campaign?: string;
  metadata?: Record<string, unknown>;
}

interface ShareEventResponse {
  deep_link_id: string;
  share_url: string;
  utm_url: string;
}

const RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1 minute
const RATE_LIMIT_MAX_REQUESTS = 30;

// Simple in-memory rate limiting
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

function generateDeepLinkId(): string {
  // Generate URL-safe 8-character ID
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789";
  let result = "";
  const randomValues = crypto.getRandomValues(new Uint8Array(8));
  for (let i = 0; i < 8; i++) {
    result += chars[randomValues[i] % chars.length];
  }
  return result;
}

function buildUtmUrl(
  baseUrl: string,
  platform: SharePlatform,
  contentType: ContentType,
  campaign?: string
): string {
  const utmParams = new URLSearchParams({
    utm_source: platform,
    utm_medium: "social_share",
    utm_campaign: campaign || `${contentType}_share`,
    utm_content: contentType,
  });
  return `${baseUrl}?${utmParams.toString()}`;
}

function getPlatformSpecificUrl(
  shareUrl: string,
  platform: SharePlatform,
  contentType: ContentType
): string {
  // Add platform-specific deep link wrappers if needed
  switch (platform) {
    case "instagram_story":
      // Instagram Stories need special handling via app
      return shareUrl;
    case "whatsapp":
      // WhatsApp can use wa.me links
      return `https://wa.me/?text=${encodeURIComponent(shareUrl)}`;
    default:
      return shareUrl;
  }
}

serve(async (req: Request) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
      },
    });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  const url = new URL(req.url);

  // GET /track-share/:id — track click and redirect
  if (req.method === "GET") {
    const pathParts = url.pathname.split("/").filter(Boolean);
    const deepLinkId = pathParts[pathParts.length - 1];

    if (!deepLinkId || deepLinkId === "track-share") {
      return new Response("Not found", { status: 404 });
    }

    try {
      // Find the share event
      const { data: shareEvent, error } = await supabase
        .from("share_events")
        .select("*, referral_codes(code)")
        .eq("deep_link_id", deepLinkId)
        .single();

      if (error || !shareEvent) {
        // Fallback to app store
        const appStoreUrl = "https://apps.apple.com/app/aura-horoscope/id0000000000";
        return new Response(null, {
          status: 302,
          headers: { Location: appStoreUrl },
        });
      }

      // Increment click count
      await supabase.rpc("increment_share_clicks", { link_id: deepLinkId });

      // Record click event for analytics
      await supabase.from("share_click_events").insert({
        share_event_id: shareEvent.id,
        user_agent: req.headers.get("User-Agent") || null,
        referrer: req.headers.get("Referer") || null,
        ip_country: req.headers.get("CF-IPCountry") || null, // Cloudflare header
      });

      // Build redirect URL with UTM params
      const baseAppUrl = "https://aura.xadev.com/open";
      const redirectUrl = buildUtmUrl(
        baseAppUrl,
        shareEvent.share_platform,
        shareEvent.content_type,
        shareEvent.utm_campaign
      );

      // Add deep link params
      const finalUrl = new URL(redirectUrl);
      finalUrl.searchParams.set("ref", deepLinkId);
      if (shareEvent.content_type) {
        finalUrl.searchParams.set("type", shareEvent.content_type);
      }
      if (shareEvent.content_id) {
        finalUrl.searchParams.set("id", shareEvent.content_id);
      }
      if (shareEvent.referral_codes?.code) {
        finalUrl.searchParams.set("referral", shareEvent.referral_codes.code);
      }

      return new Response(null, {
        status: 302,
        headers: {
          Location: finalUrl.toString(),
          "Cache-Control": "no-cache, no-store, must-revalidate",
        },
      });
    } catch (error) {
      console.error("Click tracking error:", error);
      const appStoreUrl = "https://apps.apple.com/app/aura-horoscope/id0000000000";
      return new Response(null, {
        status: 302,
        headers: { Location: appStoreUrl },
      });
    }
  }

  // POST /track-share — create share event
  if (req.method === "POST") {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
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
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    // Rate limiting
    if (isRateLimited(user.id)) {
      return new Response(
        JSON.stringify({ error: "Too many requests. Please try again later." }),
        { status: 429, headers: { "Content-Type": "application/json" } }
      );
    }

    try {
      const body: ShareEventRequest = await req.json();
      const {
        content_type,
        content_id,
        share_platform,
        utm_campaign,
        metadata,
      } = body;

      // Validate required fields
      if (!content_type || !share_platform) {
        return new Response(
          JSON.stringify({ error: "content_type and share_platform are required" }),
          { status: 400, headers: { "Content-Type": "application/json" } }
        );
      }

      // Validate content_type
      const validContentTypes: ContentType[] = [
        "reading",
        "mbti_result",
        "weekly_forecast",
        "compatibility",
        "profile",
      ];
      if (!validContentTypes.includes(content_type)) {
        return new Response(
          JSON.stringify({ error: "Invalid content_type" }),
          { status: 400, headers: { "Content-Type": "application/json" } }
        );
      }

      // Validate share_platform
      const validPlatforms: SharePlatform[] = [
        "imessage",
        "instagram",
        "instagram_story",
        "twitter",
        "facebook",
        "whatsapp",
        "telegram",
        "snapchat",
        "tiktok",
        "email",
        "copy_link",
        "other",
      ];
      if (!validPlatforms.includes(share_platform)) {
        return new Response(
          JSON.stringify({ error: "Invalid share_platform" }),
          { status: 400, headers: { "Content-Type": "application/json" } }
        );
      }

      const deepLinkId = generateDeepLinkId();

      // Get user's referral code if they have one
      const { data: userReferralCode } = await supabase
        .from("referral_codes")
        .select("id, code")
        .eq("user_id", user.id)
        .eq("is_active", true)
        .single();

      // Insert share event
      const { data: shareEvent, error: insertError } = await supabase
        .from("share_events")
        .insert({
          user_id: user.id,
          content_type,
          content_id: content_id || null,
          share_platform,
          deep_link_id: deepLinkId,
          utm_campaign: utm_campaign || `${content_type}_share`,
          referral_code_id: userReferralCode?.id || null,
          metadata: metadata || null,
        })
        .select()
        .single();

      if (insertError) {
        console.error("Share event insert error:", insertError);
        throw insertError;
      }

      // Build URLs
      const baseShareUrl = `https://aura.xadev.com/share/${deepLinkId}`;
      const utmUrl = buildUtmUrl(baseShareUrl, share_platform, content_type, utm_campaign);

      // Add referral code to URL if user has one
      let finalUrl = utmUrl;
      if (userReferralCode?.code) {
        finalUrl = `${utmUrl}&ref=${userReferralCode.code}`;
      }

      const response: ShareEventResponse = {
        deep_link_id: deepLinkId,
        share_url: baseShareUrl,
        utm_url: finalUrl,
      };

      return new Response(JSON.stringify(response), {
        status: 200,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      });
    } catch (error) {
      console.error("Share event error:", error);
      return new Response(
        JSON.stringify({ error: "Failed to create share event" }),
        {
          status: 500,
          headers: {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
          },
        }
      );
    }
  }

  return new Response("Method not allowed", { status: 405 });
});
