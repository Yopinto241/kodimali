import { createClient } from "npm:@supabase/supabase-js@2";
import { json } from "../_shared/clickpesa.ts";
import { mapSonicPesaStatus } from "../_shared/sonicpesa.ts";

const encoder = new TextEncoder();
const hex = (bytes: ArrayBuffer) => [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
const safeEqual = (a: string, b: string) => {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return difference === 0;
};
async function validSignature(raw: string, supplied: string, secret: string) {
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(raw));
  const expectedHex = hex(signature);
  const expectedBase64 = btoa(String.fromCharCode(...new Uint8Array(signature)));
  const normalized = supplied.trim().replace(/^sha256=/i, "");
  return safeEqual(normalized.toLowerCase(), expectedHex) || safeEqual(normalized, expectedBase64);
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const raw = await request.text();
  const secret = (Deno.env.get("SONICPESA_WEBHOOK_SECRET") ?? "").trim();
  const signature = request.headers.get("x-sonicpesa-signature") ?? request.headers.get("x-signature") ?? request.headers.get("signature") ?? "";
  if (!secret || !signature || !(await validSignature(raw, signature, secret))) return json({ error: "Invalid webhook signature" }, 401);
  const db = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
  try {
    const payload = JSON.parse(raw) as Record<string, unknown>;
    const orderId = String(payload.order_id ?? "").trim();
    const transactionId = String(payload.transid ?? "").trim();
    const event = String(payload.event ?? "payment.updated");
    const status = mapSonicPesaStatus(payload.status);
    if (!orderId) return json({ error: "order_id is required" }, 400);
    const digest = hex(await crypto.subtle.digest("SHA-256", encoder.encode(raw)));
    const providerEventId = `${orderId}:${event}:${transactionId || status}`;
    const { error: eventError } = await db.from("payment_webhook_events").insert({ provider: "sonicpesa", provider_event_id: providerEventId, payload_digest: digest, signature_verified: true });
    if (eventError?.code === "23505") return json({ received: true, duplicate: true });
    if (eventError) throw new Error(eventError.message);

    const { data: platform } = await db.from("platform_payment_orders").select("id").eq("provider_order_id", orderId).maybeSingle();
    if (platform?.id) {
      if (status === "paid") {
        const { error } = await db.rpc("finalize_platform_payment", { p_order_id: platform.id, p_provider_transaction_id: transactionId || orderId, p_provider_payload: payload });
        if (error) throw new Error(error.message);
      } else await db.from("platform_payment_orders").update({ status, provider_transaction_id: transactionId || null, provider_response: payload, updated_at: new Date().toISOString() }).eq("id", platform.id);
    } else {
      const tables = ["listing_contact_payments", "listing_chat_payments", "agent_listing_payments", "agent_commercial_payments"];
      let applied = false;
      for (const table of tables) {
        const { data: row } = await db.from(table).select("id").eq("provider_payment_id", orderId).maybeSingle();
        if (!row?.id) continue;
        const update: Record<string, unknown> = { payment_status: status, provider_payment_reference: transactionId || null, provider_response: payload, paid_at: status === "paid" ? new Date().toISOString() : null, status_message: String(payload.message ?? "") || null, updated_at: new Date().toISOString() };
        if (table !== "agent_commercial_payments") Object.assign(update, { webhook_payload: payload, webhook_received_at: new Date().toISOString() });
        const { error } = await db.from(table).update(update).eq("id", row.id);
        if (error) throw new Error(error.message);
        if (status === "paid" && table === "listing_chat_payments") await db.rpc("grant_listing_chat_access", { p_payment_id: row.id });
        if (status === "paid" && table === "agent_listing_payments") await db.rpc("release_agent_listing_if_eligible", { p_listing_id: (await db.from(table).select("listing_id").eq("id", row.id).single()).data?.listing_id });
        applied = true;
        break;
      }
      if (!applied) throw new Error("Payment order was not found");
    }
    await db.from("payment_webhook_events").update({ processed_at: new Date().toISOString() }).eq("provider_event_id", providerEventId);
    return json({ received: true });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Webhook processing failed" }, 500);
  }
});
