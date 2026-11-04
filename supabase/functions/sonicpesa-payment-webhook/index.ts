import { applyPaymentEvent, completePaymentEvidence, paymentEvidence } from "../_shared/payment-integrity.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { json } from "../_shared/clickpesa.ts";
import { checkSonicPesaOrder, mapSonicPesaStatus } from "../_shared/sonicpesa.ts";

const encoder = new TextEncoder();
const hex = (bytes: ArrayBuffer) =>
  [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join(
    "",
  );
const safeEqual = (a: string, b: string) => {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let i = 0; i < a.length; i++) {
    difference |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return difference === 0;
};
async function validSignature(raw: string, supplied: string, secret: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(raw));
  const expectedHex = hex(signature);
  const expectedBase64 = btoa(
    String.fromCharCode(...new Uint8Array(signature)),
  );
  const normalized = supplied.trim().replace(/^sha256=/i, "");
  return safeEqual(normalized.toLowerCase(), expectedHex) ||
    safeEqual(normalized, expectedBase64);
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  const raw = await request.text();
  const secret = (Deno.env.get("SONICPESA_WEBHOOK_SECRET") ?? "").trim();
  const signature = request.headers.get("x-sonicpesa-signature") ??
    request.headers.get("x-signature") ?? request.headers.get("signature") ??
    "";
  if (
    !secret || !signature || !(await validSignature(raw, signature, secret))
  ) return json({ error: "Invalid webhook signature" }, 401);
  const db = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  try {
    const payload = JSON.parse(raw) as Record<string, unknown>;
    const orderId = String(payload.order_id ?? "").trim();
    const transactionId = String(payload.transid ?? "").trim();
    const event = String(payload.event ?? "payment.updated");
    const status = mapSonicPesaStatus(payload.status);
    if (!orderId) return json({ error: "order_id is required" }, 400);
    const digest = hex(
      await crypto.subtle.digest("SHA-256", encoder.encode(raw)),
    );
    const providerEventId = `${orderId}:${event}:${transactionId || status}`;
    const { data: claimed, error: claimError } = await db.rpc(
      "claim_payment_webhook_event",
      {
        p_provider: "sonicpesa",
        p_provider_event_id: providerEventId,
        p_payload_digest: digest,
        p_signature_verified: true,
      },
    );
    if (claimError) throw new Error(claimError.message);
    if (claimed !== true) return json({ received: true, duplicate: true });

    let verifiedPayload: unknown = payload;
    let verifiedStatus = status;
    if (status === "paid" && !completePaymentEvidence(paymentEvidence("sonicpesa", payload))) {
      try {
        const verified = await checkSonicPesaOrder(orderId);
        verifiedPayload = verified.payload;
        verifiedStatus = verified.status;
      } catch {
        // Incomplete evidence goes to the atomic reconciliation path; no grant.
      }
    }
    const tables = ["platform_payment_orders", "listing_contact_payments", "listing_chat_payments", "agent_listing_payments", "agent_commercial_payments"];
    let applied = false;
    for (const table of tables) {
      const orderColumn = table === "platform_payment_orders" ? "provider_order_id" : "provider_payment_id";
      const { data: row, error } = await db.from(table).select("id").eq(orderColumn, orderId).maybeSingle();
      if (error) throw new Error("Payment lookup is temporarily unavailable");
      if (!row?.id) continue;
      const result = await applyPaymentEvent(db, table, row.id, "sonicpesa", verifiedStatus, verifiedPayload);
      if (result.reconciliationRequired) {
        await db.rpc("finish_payment_webhook_event", { p_provider: "sonicpesa", p_provider_event_id: providerEventId, p_status: "reconciliation_required", p_error: "Provider evidence requires review" });
        return json({ received: true, reconciliationRequired: true });
      }
      applied = true;
      break;
    }
    if (!applied) throw new Error("Payment order was not found");
    await db.rpc("finish_payment_webhook_event", {
      p_provider: "sonicpesa",
      p_provider_event_id: providerEventId,
      p_status: "processed",
      p_error: null,
    });
    return json({ received: true });
  } catch (error) {
    try {
      const payload = JSON.parse(raw) as Record<string, unknown>;
      const orderId = String(payload.order_id ?? "").trim();
      const transactionId = String(payload.transid ?? "").trim();
      const event = String(payload.event ?? "payment.updated");
      const failedStatus = mapSonicPesaStatus(payload.status);
      if (orderId) {
        await db.rpc("finish_payment_webhook_event", {
          p_provider: "sonicpesa",
          p_provider_event_id: `${orderId}:${event}:${
            transactionId || failedStatus
          }`,
          p_status: "failed",
          p_error: error instanceof Error
            ? error.message
            : "Webhook processing failed",
        });
      }
    } catch { /* The original error remains authoritative. */ }
    return json({
      error: error instanceof Error
        ? error.message
        : "Webhook processing failed",
    }, 500);
  }
});
