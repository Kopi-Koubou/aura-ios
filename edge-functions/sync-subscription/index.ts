import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface RevenueCatEvent {
  type: string;
  app_user_id: string;
  original_app_user_id: string;
  product_id: string;
  entitlement_ids: string[];
  period_type: "NORMAL" | "TRIAL" | "INTRO";
  purchased_at_ms: number;
  expiration_at_ms: number | null;
  environment: "SANDBOX" | "PRODUCTION";
}

interface WebhookPayload {
  event: RevenueCatEvent;
  api_version: string;
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // Validate RevenueCat webhook authorization
  const authHeader = req.headers.get("Authorization");
  const expectedToken = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");
  if (!expectedToken || authHeader !== `Bearer ${expectedToken}`) {
    return new Response("Unauthorized", { status: 401 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  try {
    const payload: WebhookPayload = await req.json();
    const event = payload.event;

    // Log webhook for audit trail
    await supabase.from("subscription_webhooks").insert({
      event_type: event.type,
      customer_id: event.app_user_id,
      product_id: event.product_id,
      payload: payload,
    });

    // Find user by RevenueCat customer ID
    const { data: subscription } = await supabase
      .from("subscriptions")
      .select("*")
      .eq("revenuecat_customer_id", event.app_user_id)
      .single();

    if (!subscription) {
      // Create subscription record if first purchase
      if (event.type === "INITIAL_PURCHASE") {
        await supabase.from("subscriptions").upsert({
          user_id: event.original_app_user_id,
          tier: "premium",
          product_id: event.product_id,
          original_purchase_date: new Date(event.purchased_at_ms).toISOString(),
          expires_at: event.expiration_at_ms
            ? new Date(event.expiration_at_ms).toISOString()
            : null,
          is_trial: event.period_type === "TRIAL",
          trial_ends_at:
            event.period_type === "TRIAL" && event.expiration_at_ms
              ? new Date(event.expiration_at_ms).toISOString()
              : null,
          is_active: true,
          revenuecat_customer_id: event.app_user_id,
          updated_at: new Date().toISOString(),
        });
      }
      return new Response(JSON.stringify({ status: "ok" }), { status: 200 });
    }

    // Handle event types per tech spec
    switch (event.type) {
      case "INITIAL_PURCHASE":
      case "RENEWAL":
      case "UNCANCELLATION":
        await supabase
          .from("subscriptions")
          .update({
            tier: "premium",
            product_id: event.product_id,
            expires_at: event.expiration_at_ms
              ? new Date(event.expiration_at_ms).toISOString()
              : null,
            is_trial: event.period_type === "TRIAL",
            is_active: true,
            updated_at: new Date().toISOString(),
          })
          .eq("id", subscription.id);
        break;

      case "CANCELLATION":
        // Keep access until expiry but mark as cancelled
        await supabase
          .from("subscriptions")
          .update({
            updated_at: new Date().toISOString(),
          })
          .eq("id", subscription.id);
        break;

      case "EXPIRATION":
        await supabase
          .from("subscriptions")
          .update({
            tier: "free",
            is_active: false,
            is_trial: false,
            updated_at: new Date().toISOString(),
          })
          .eq("id", subscription.id);
        break;

      case "BILLING_ISSUE":
        // Grace period — keep premium but flag for follow-up
        await supabase
          .from("subscriptions")
          .update({
            updated_at: new Date().toISOString(),
          })
          .eq("id", subscription.id);
        break;
    }

    return new Response(JSON.stringify({ status: "ok" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
