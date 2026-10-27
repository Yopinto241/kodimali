import { createClient } from "npm:@supabase/supabase-js@2";
import {
  createCollectionOrder,
  PaymentProviderError,
} from "../_shared/payment-provider.ts";
import { json, normalizePhoneNumber } from "../_shared/clickpesa.ts";

const allowedProducts = new Set(["booking_deposit", "booking_balance"]);

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return json({ ok: true });
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  const authorization = request.headers.get("Authorization") ?? "";
  const jwt = authorization.replace(/^Bearer\s+/i, "");
  const db = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  try {
    const { data: { user } } = await db.auth.getUser(jwt);
    if (!user) return json({ error: "Sign in before paying." }, 401);
    const body = await request.json() as Record<string, unknown>;
    const bookingId = String(body.booking_id ?? "").trim();
    const product = String(body.product ?? "").trim();
    const phone = normalizePhoneNumber(String(body.phone_number ?? ""));
    const idempotencyKey = String(body.idempotency_key ?? "").trim();
    if (
      !bookingId || !allowedProducts.has(product) || idempotencyKey.length < 12
    ) return json({ error: "Invalid booking payment request." }, 400);
    if (phone.length < 12) {
      return json({ error: "Enter a valid mobile-money number." }, 400);
    }
    const userDb = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: `Bearer ${jwt}` } } },
    );
    const preparation = await userDb.rpc("prepare_booking_payment_intent", {
      p_booking_id: bookingId,
      p_product: product,
      p_idempotency_key: idempotencyKey,
    });
    if (preparation.error) throw new Error(preparation.error.message);
    const prepared = preparation.data as Record<string, unknown>;
    const intentId = String(prepared.payment_intent_id ?? "");
    const amount = Number(prepared.amount_minor ?? 0);
    if (!intentId || !Number.isSafeInteger(amount) || amount < 1000) {
      throw new Error("The server returned an invalid payment amount.");
    }
    const { data: existing } = await db.from("platform_payment_orders").select(
      "id,status,provider,provider_order_id,amount_tzs",
    ).eq("payment_intent_id", intentId).maybeSingle();
    if (existing?.provider_order_id) {
      return json({
        success: true,
        paymentId: existing.id,
        paymentIntentId: intentId,
        paymentStatus: existing.status,
        amount: existing.amount_tzs,
        currency: "TZS",
        provider: existing.provider,
      });
    }
    const reference = `K3${
      crypto.randomUUID().replaceAll("-", "").slice(0, 20).toUpperCase()
    }`;
    const { data: orderRow, error: insertError } = await db.from(
      "platform_payment_orders",
    ).insert({
      user_id: user.id,
      purpose: product,
      resource_id: bookingId,
      payment_intent_id: intentId,
      order_reference: reference,
      amount_tzs: amount,
      customer_phone_number: phone,
    }).select("id").single();
    if (insertError) throw new Error(insertError.message);
    try {
      const order = await createCollectionOrder({
        phone,
        amount,
        email: user.email,
        name: String(user.user_metadata?.full_name ?? "KODIMALI customer"),
      });
      await db.from("platform_payment_orders").update({
        provider: order.provider,
        provider_order_id: order.orderId,
        status: order.status,
        provider_response: order.payload,
      }).eq("id", orderRow.id);
      await db.from("payment_intents").update({
        provider: order.provider,
        provider_order_id: order.orderId,
        status: order.status === "processing"
          ? "processing"
          : "awaiting_payment",
        updated_at: new Date().toISOString(),
      }).eq("id", intentId);
      return json({
        success: true,
        paymentId: orderRow.id,
        paymentIntentId: intentId,
        paymentStatus: order.status,
        amount,
        currency: "TZS",
        provider: order.provider,
      });
    } catch (error) {
      await db.from("platform_payment_orders").update({
        status: "failed",
        status_message: error instanceof Error
          ? error.message
          : "Payment failed",
      }).eq("id", orderRow.id);
      await db.from("payment_intents").update({
        status: "failed",
        updated_at: new Date().toISOString(),
      }).eq("id", intentId);
      throw error;
    }
  } catch (error) {
    return json({
      error: error instanceof Error
        ? error.message
        : "Could not start booking payment.",
    }, error instanceof PaymentProviderError ? error.status : 500);
  }
});
