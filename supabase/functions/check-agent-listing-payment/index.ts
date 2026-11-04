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
  const service = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  try {
    const token = (request.headers.get("Authorization") ?? "").replace(
      /^Bearer\s+/i,
      "",
    );
    const { data: { user } } = await service.auth.getUser(token);
    if (!user) return json({ error: "Sign in again." }, 401);
    const paymentId = String((await request.json())?.payment_id ?? "");
    const { data: agent } = await service.from("agents").select("id").eq(
      "profile_id",
      user.id,
    ).single();
    if (!agent) return json({ error: "Active agent account required." }, 403);
    const { data: payment } = await service.from("agent_listing_payments")
      .select(
        "id,listing_id,order_reference,payment_status,provider_payment_id",
      ).eq("id", paymentId).eq("agent_id", agent?.id ?? "").single();
    if (!payment) return json({ error: "Payment not found." }, 404);
    const { data: fee, error: feeError } = await service.rpc(
      "agent_listing_publication_fee", { p_agent_id: agent.id },
    );
    if (feeError) throw new Error(feeError.message);
    if (typeof fee !== "number" || fee < 0) throw new Error("Publication settings unavailable");
    if (fee === 0) {
      const { data: published, error } = await service.rpc(
        "release_agent_listing_if_eligible", { p_listing_id: payment.listing_id },
      );
      if (error) throw new Error(error.message);
      // Do not mark an unpaid provider transaction paid or cancel it implicitly.
      return json({ success: true, paymentRequired: false, paymentStatus: "free", published: published === true });
    }
    if (
      !["paid", "failed", "expired", "cancelled"].includes(
        payment.payment_status,
      )
    ) {
      if (String(payment.provider_payment_id ?? "").startsWith("sp_")) {
        const result = await checkSonicPesaOrder(
          String(payment.provider_payment_id),
        );
        payment.payment_status = (await applyPaymentEvent(service, "agent_listing_payments", payment.id, "sonicpesa", result.status, result.payload)).status;
      } else {
        const config = readClickPesaConfig({
          clientIdEnv: "CLICKPESA_COLLECTION_CLIENT_ID",
          apiKeyEnv: "CLICKPESA_COLLECTION_API_KEY",
          checksumKeyEnv: "CLICKPESA_COLLECTION_CHECKSUM_KEY",
        });
        const access = await fetchClickPesaToken(config);
        const row = await queryPaymentStatus(
          config,
          access,
          payment.order_reference,
        );
        if (row) {
          payment.payment_status = (await applyPaymentEvent(service, "agent_listing_payments", payment.id, "clickpesa", mapClickPesaStatus(row?.status), row)).status;
        }
      }
    }
    if (payment.payment_status === "paid") {
      const { error: publishError } = await service.rpc(
        "release_agent_listing_if_eligible",
        { p_listing_id: payment.listing_id },
      );
      if (publishError) throw new Error(publishError.message);
    }
    return json({ success: true, paymentStatus: payment.payment_status });
  } catch (error) {
    return json({
      error: error instanceof Error
        ? error.message
        : "Could not check payment.",
    }, 500);
  }
});
