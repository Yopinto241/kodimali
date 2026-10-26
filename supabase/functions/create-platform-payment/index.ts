import { createClient } from "npm:@supabase/supabase-js@2";
import { createSonicPesaOrder, SonicPesaRequestError } from "../_shared/sonicpesa.ts";
import { json, normalizePhoneNumber } from "../_shared/clickpesa.ts";

const reference = (purpose: string) => `${purpose === "booking_reservation" ? "BK" : "EV"}${crypto.randomUUID().replaceAll("-", "").slice(0, 18).toUpperCase()}`;

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return json({ ok: true });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const db = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
  try {
    const jwt = (request.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: { user } } = await db.auth.getUser(jwt);
    if (!user) return json({ error: "Sign in before paying." }, 401);
    const body = await request.json();
    const purpose = String(body?.purpose ?? "");
    const resourceId = String(body?.resource_id ?? "");
    if (!["booking_reservation", "event_deposit", "event_balance"].includes(purpose) || !resourceId) return json({ error: "Invalid payment request." }, 400);
    const { data: enabled, error: enabledError } = await db.rpc("payment_feature_enabled", { p_purpose: purpose });
    if (enabledError) throw new Error(enabledError.message);

    const userDb = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_ANON_KEY") ?? "", { global: { headers: { Authorization: `Bearer ${jwt}` } } });
    if (enabled !== true) {
      if (purpose !== "booking_reservation") return json({ error: "This payment option is not enabled." }, 503);
      const freeConfirmation = await userDb.rpc("confirm_free_booking", { p_booking_id: resourceId });
      if (freeConfirmation.error) throw new Error(freeConfirmation.error.message);
      return json({ success: true, paymentRequired: false, paymentStatus: "free", confirmed: true, amount: 0, currency: "TZS", resourceId });
    }
    const phone = normalizePhoneNumber(String(body?.phone_number ?? ""));
    if (phone.length < 12) return json({ error: "Enter a valid mobile-money number." }, 400);
    const preparation = purpose === "booking_reservation"
      ? await userDb.rpc("prepare_booking_for_payment", { p_booking_id: resourceId })
      : await userDb.rpc("prepare_event_for_payment", { p_plan_id: resourceId, p_kind: purpose });
    if (preparation.error) throw new Error(preparation.error.message);
    const amount = Number((preparation.data as Record<string, unknown>)?.amount_tzs ?? 0);
    if (!Number.isFinite(amount) || amount < 1000) throw new Error("The server returned an invalid payment amount.");

    const { data: existing } = await db.from("platform_payment_orders").select("id,status,provider_order_id,amount_tzs").eq("purpose", purpose).eq("resource_id", resourceId).in("status", ["pending", "processing", "paid"]).maybeSingle();
    if (existing?.status === "paid") return json({ success: true, paymentId: existing.id, paymentStatus: "paid", amount: existing.amount_tzs, currency: "TZS" });
    if (existing?.provider_order_id) return json({ success: true, paymentId: existing.id, paymentStatus: existing.status, amount: existing.amount_tzs, currency: "TZS", provider: "sonicpesa" });

    const orderReference = reference(purpose);
    const { data: payment, error: insertError } = await db.from("platform_payment_orders").insert({ user_id: user.id, purpose, resource_id: resourceId, order_reference: orderReference, amount_tzs: amount, customer_phone_number: phone }).select("id").single();
    if (insertError) throw new Error(insertError.message);
    try {
      const order = await createSonicPesaOrder({ phone, amount, email: user.email, name: String(user.user_metadata?.full_name ?? "KODIMALI customer") });
      await db.from("platform_payment_orders").update({ provider_order_id: order.orderId, status: order.status, provider_response: order.payload }).eq("id", payment.id);
      return json({ success: true, paymentId: payment.id, paymentStatus: order.status, amount, currency: "TZS", provider: "sonicpesa" });
    } catch (error) {
      await db.from("platform_payment_orders").update({ status: "failed", status_message: error instanceof Error ? error.message : "Payment failed" }).eq("id", payment.id);
      throw error;
    }
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Could not start payment." }, error instanceof SonicPesaRequestError ? error.status : 500);
  }
});
