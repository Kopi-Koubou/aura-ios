import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req: Request) => {
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
    return new Response("Unauthorized", { status: 401 });
  }
  const token = authHeader.replace("Bearer ", "");
  const {
    data: { user },
  } = await supabase.auth.getUser(token);
  if (!user) {
    return new Response("Unauthorized", { status: 401 });
  }

  try {
    const { revenuecat_customer_id } = await req.json();

    // Validate with RevenueCat REST API
    const rcApiKey = Deno.env.get("REVENUECAT_API_KEY")!;
    const rcResponse = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${revenuecat_customer_id}`,
      {
        headers: {
          Authorization: `Bearer ${rcApiKey}`,
          "Content-Type": "application/json",
        },
      }
    );

    if (!rcResponse.ok) {
      return new Response(
        JSON.stringify({ error: "RevenueCat validation failed" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const rcData = await rcResponse.json();
    const entitlements = rcData.subscriber?.entitlements?.premium;
    const isActive = entitlements?.expires_date
      ? new Date(entitlements.expires_date) > new Date()
      : false;

    // Sync subscription state to database
    await supabase.from("subscriptions").upsert(
      {
        user_id: user.id,
        tier: isActive ? "premium" : "free",
        product_id: entitlements?.product_identifier ?? null,
        is_active: isActive,
        revenuecat_customer_id,
        expires_at: entitlements?.expires_date ?? null,
        is_trial: entitlements?.period_type === "trial",
        updated_at: new Date().toISOString(),
      },
      { onConflict: "user_id" }
    );

    return new Response(
      JSON.stringify({
        is_premium: isActive,
        expires_at: entitlements?.expires_date ?? null,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (error) {
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
