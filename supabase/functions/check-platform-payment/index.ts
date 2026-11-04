import { applyPaymentEvent } from "../_shared/payment-integrity.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  checkCollectionOrder,
  PaymentProviderError,
} from "../_shared/payment-provider.ts";
import { json } from "../_shared/clickpesa.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return json({ ok: true });
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  const db = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  try {
    const jwt = (request.headers.get("Authorization") ?? "").replace(
      /^Bearer\s+/i,
      "",
    );
    const { data: { user } } = await db.auth.getUser(jwt);
    if (!user) return json({ error: "Sign in before checking payment." }, 401);
    const paymentId = String((await request.json())?.payment_id ?? "");
    const { data: payment } = await db.from("platform_payment_orders").select(
      "*",
    ).eq("id", paymentId).eq("user_id", user.id).single();
    if (!payment) return json({ error: "Payment was not found." }, 404);
    let status = String(payment.status);
    if (
      !["paid", "failed", "cancelled", "expired", "refunded"].includes(status)
    ) {
      if (!payment.provider_order_id) {
        throw new Error("Payment provider order is missing.");
      }
      const result = await checkCollectionOrder(
        payment.provider,
        String(payment.provider_order_id),
      );
      const applied = await applyPaymentEvent(db, "platform_payment_orders", payment.id, "sonicpesa", result.status, result.payload);
      status = applied.status;
    }
    return json({
      success: true,
      paymentStatus: status,
      amount: payment.amount_tzs,
      currency: payment.currency,
      purpose: payment.purpose,
      resourceId: payment.resource_id,
    });
  } catch (error) {
    return json({
      error: error instanceof Error
        ? error.message
        : "Could not check payment.",
    }, error instanceof PaymentProviderError ? error.status : 500);
  }
});
