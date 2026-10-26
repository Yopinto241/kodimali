import { createClient } from "npm:@supabase/supabase-js@2";
import { fetchClickPesaToken, json, mapClickPesaStatus, queryPaymentStatus, readClickPesaConfig } from "../_shared/clickpesa.ts";
import { checkSonicPesaOrder } from "../_shared/sonicpesa.ts";
Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const service = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
  try {
    const token = (request.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: { user } } = await service.auth.getUser(token);
    if (!user) return json({ error: "Sign in again." }, 401);
    const paymentId = String((await request.json())?.payment_id ?? "");
    const { data: agent } = await service.from("agents").select("id").eq("profile_id", user.id).single();
    const { data: payment } = await service.from("agent_listing_payments").select("id,listing_id,order_reference,payment_status,provider_payment_id").eq("id", paymentId).eq("agent_id", agent?.id ?? "").single();
    if (!payment) return json({ error: "Payment not found." }, 404);
    if (!["paid","failed","expired","cancelled"].includes(payment.payment_status)) {
      if (String(payment.provider_payment_id ?? "").startsWith("sp_")) {
        const result = await checkSonicPesaOrder(String(payment.provider_payment_id));
        await service.from("agent_listing_payments").update({ payment_status: result.status, paid_at: result.status === "paid" ? new Date().toISOString() : null, provider_payment_reference: result.transactionId, provider_channel: result.channel, provider_response: result.payload }).eq("id", payment.id);
        payment.payment_status = result.status;
      } else {
        const config = readClickPesaConfig({ clientIdEnv: "CLICKPESA_COLLECTION_CLIENT_ID", apiKeyEnv: "CLICKPESA_COLLECTION_API_KEY", checksumKeyEnv: "CLICKPESA_COLLECTION_CHECKSUM_KEY" });
        const access = await fetchClickPesaToken(config); const row = await queryPaymentStatus(config, access, payment.order_reference);
        if (row) { const status = mapClickPesaStatus(row?.status); await service.from("agent_listing_payments").update({ payment_status: status, paid_at: status === "paid" ? new Date().toISOString() : null }).eq("id", payment.id); payment.payment_status = status; }
      }
    }
    if (payment.payment_status === "paid") {
      const { error: publishError } = await service.rpc("release_agent_listing_if_eligible", { p_listing_id: payment.listing_id });
      if (publishError) throw new Error(publishError.message);
    }
    return json({ success: true, paymentStatus: payment.payment_status });
  } catch (error) { return json({ error: error instanceof Error ? error.message : "Could not check payment." }, 500); }
});
