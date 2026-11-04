import { applyPaymentEvent } from "../_shared/payment-integrity.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  fetchClickPesaToken,
  json,
  mapClickPesaStatus,
  queryPaymentStatus,
  readClickPesaConfig,
} from "../_shared/clickpesa.ts";
import { checkSonicPesaOrder } from "../_shared/sonicpesa.ts";
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
    if (!user) return json({ error: "Sign in again." }, 401);
    const paymentId = String((await request.json())?.payment_id ?? "");
    const { data: p } = await db.from("listing_chat_payments").select(
      "id,order_reference,payment_status,listing_id,provider_payment_id",
    ).eq("id", paymentId).eq("customer_id", user.id).single();
    if (!p) return json({ error: "Payment not found." }, 404);
    let status = p.payment_status;
    if (!["paid", "failed", "expired", "cancelled"].includes(status)) {
      if (String(p.provider_payment_id ?? "").startsWith("sp_")) {
        const result = await checkSonicPesaOrder(String(p.provider_payment_id));
        status = (await applyPaymentEvent(db, "listing_chat_payments", p.id, "sonicpesa", result.status, result.payload)).status;
      } else {
        const config = readClickPesaConfig({
          clientIdEnv: "CLICKPESA_COLLECTION_CLIENT_ID",
          apiKeyEnv: "CLICKPESA_COLLECTION_API_KEY",
          checksumKeyEnv: "CLICKPESA_COLLECTION_CHECKSUM_KEY",
        });
        const token = await fetchClickPesaToken(config);
        const result = await queryPaymentStatus(
          config,
          token,
          p.order_reference,
        );
        status = (await applyPaymentEvent(db, "listing_chat_payments", p.id, "clickpesa", mapClickPesaStatus(result?.status), result)).status;
      }
    }
    let expiresAt = null;
    if (status === "paid") {
      const { data: a } = await db.from("listing_chat_access").select(
        "expires_at",
      ).eq("customer_id", user.id).eq("listing_id", p.listing_id).maybeSingle();
      expiresAt = a?.expires_at ?? null;
    }
    return json({ success: true, paymentStatus: status, expiresAt });
  } catch (error) {
    return json({
      error: error instanceof Error
        ? error.message
        : "Could not check chat payment.",
    }, 500);
  }
});
