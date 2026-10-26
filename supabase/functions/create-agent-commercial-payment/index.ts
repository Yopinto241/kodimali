import { createClient } from "npm:@supabase/supabase-js@2";
import { json, normalizePhoneNumber } from "../_shared/clickpesa.ts";
import { createSonicPesaOrder, SonicPesaRequestError } from "../_shared/sonicpesa.ts";
const reference = () => `BZ${crypto.randomUUID().replaceAll("-", "").slice(0, 18).toUpperCase()}`;
Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const db = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
  try {
    const jwt = (request.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: { user } } = await db.auth.getUser(jwt);
    if (!user) return json({ error: "Sign in as an agent." }, 401);
    const { data: agent } = await db.from("agents").select("id").eq("profile_id", user.id).single();
    if (!agent) return json({ error: "Agent account not found." }, 403);
    const body = await request.json(); const type = String(body?.product_type ?? ""); const phone = normalizePhoneNumber(String(body?.phone_number ?? ""));
    let amount = 0, planId: string | null = null, boostId: string | null = null;
    if (type === "subscription") { planId = String(body?.plan_id ?? ""); const { data: plan } = await db.from("agent_subscription_plans").select("monthly_price_tzs,is_active").eq("id", planId).single(); if (!plan?.is_active || Number(plan.monthly_price_tzs) <= 0) return json({ error: "Choose a paid active plan." }, 400); amount = Number(plan.monthly_price_tzs); }
    else if (type === "listing_boost") { boostId = String(body?.listing_boost_id ?? ""); const { data: boost } = await db.from("listing_boosts").select("amount_tzs,agent_id,status").eq("id", boostId).single(); if (!boost || boost.agent_id !== agent.id || boost.status !== "pending") return json({ error: "Boost request is unavailable." }, 400); amount = Number(boost.amount_tzs); }
    else return json({ error: "Unsupported product." }, 400);
    const { data: enabled, error: settingError } = await db.rpc("commercial_payment_enabled", { p_product_type: type }); if (settingError) throw new Error(settingError.message);
    if (enabled !== true) return json({ error: "Paid subscriptions or promotions are currently unavailable. Ask an administrator for a complimentary entitlement." }, 503);
    if (phone.length < 12) return json({ error: "Enter a valid mobile-money number." }, 400);
    const { data: payment, error } = await db.from("agent_commercial_payments").insert({ agent_id: agent.id, product_type: type, plan_id: planId, listing_boost_id: boostId, order_reference: reference(), requested_amount: amount, customer_phone_number: phone, payment_provider: "sonicpesa" }).select("id").single(); if (error) throw new Error(error.message);
    try { const order = await createSonicPesaOrder({ phone, amount, email: user.email, name: String(user.user_metadata?.full_name ?? "KODIMALI agent") }); await db.from("agent_commercial_payments").update({ payment_status: order.status, provider_payment_id: order.orderId, provider_channel: order.channel, provider_response: order.payload }).eq("id", payment.id); return json({ success: true, paymentRequired: true, paymentId: payment.id, paymentStatus: order.status, amount, currency: "TZS", provider: "sonicpesa" }); }
    catch (caught) { await db.from("agent_commercial_payments").update({ payment_status: "failed", failed_at: new Date().toISOString(), status_message: caught instanceof Error ? caught.message : "Payment failed" }).eq("id", payment.id); throw caught; }
  } catch (error) { return json({ error: error instanceof Error ? error.message : "Could not start payment." }, error instanceof SonicPesaRequestError ? error.status : 500); }
});
