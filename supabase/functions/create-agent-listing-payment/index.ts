import { createClient } from "npm:@supabase/supabase-js@2";
import { ClickPesaRequestError, createChecksum, fetchClickPesaToken, formatAmount, initiateUssdPushRequest, json, mapClickPesaStatus, normalizePhoneNumber, previewUssdPushRequest, readClickPesaConfig } from "../_shared/clickpesa.ts";

const orderReference = () => `AL${crypto.randomUUID().replaceAll("-", "").slice(0, 18).toUpperCase()}`;

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const service = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
  try {
    const token = (request.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: { user } } = await service.auth.getUser(token);
    if (!user) return json({ error: "Sign in again before paying." }, 401);
    const listingId = String((await request.json())?.listing_id ?? "").trim();
    const { data: agent } = await service.from("agents").select("id, phone_number").eq("profile_id", user.id).eq("account_status", "active").single();
    const { data: listing } = await service.from("listings").select("id,status,agent_id").eq("id", listingId).eq("agent_id", agent?.id ?? "").single();
    if (!agent || !listing) return json({ error: "This listing does not belong to your active agent account." }, 403);
    const { data: enabled, error: settingError } = await service.rpc("agent_listing_payments_enabled");
    if (settingError) throw new Error(settingError.message);
    const {error:capacityError}=await service.rpc("assert_agent_plan_listing_capacity",{p_agent_id:agent.id,p_listing_id:listingId});
    if(capacityError)throw new Error(capacityError.message);
    const {data:subscription}=await service.from("agent_subscriptions").select("plan_id,agent_subscription_plans(publication_fee_tzs)").eq("agent_id",agent.id).eq("status","active").or(`expires_at.is.null,expires_at.gt.${new Date().toISOString()}`).limit(1).maybeSingle();
    const planData=subscription?.agent_subscription_plans as unknown as {publication_fee_tzs?:number}|null;
    const amount=Number(planData?.publication_fee_tzs??1000);
    if (enabled === false || amount === 0) {
      const { data: published, error: publishError } = await service.rpc("release_agent_listing_if_eligible", { p_listing_id: listingId });
      if (publishError) throw new Error(publishError.message);
      return json({ success: true, paymentRequired: false, paymentStatus: "free", published: published === true });
    }
    const phone = normalizePhoneNumber(String(agent.phone_number ?? ""));
    if (phone.length < 12) return json({ error: "Add a valid mobile-money phone number to your agent profile." }, 400);
    const { data: existing } = await service.from("agent_listing_payments").select("id,payment_status,order_reference").eq("listing_id", listingId).maybeSingle();
    if (existing?.payment_status === "paid") {
      const { data: published, error: publishError } = await service.rpc("release_agent_listing_if_eligible", { p_listing_id: listingId });
      if (publishError) throw new Error(publishError.message);
      return json({ success: true, paymentRequired: true, paymentId: existing.id, paymentStatus: "paid", published: published === true });
    }
    const config = readClickPesaConfig({ clientIdEnv: "CLICKPESA_COLLECTION_CLIENT_ID", apiKeyEnv: "CLICKPESA_COLLECTION_API_KEY", checksumKeyEnv: "CLICKPESA_COLLECTION_CHECKSUM_KEY" });
    const reference = existing?.order_reference ?? orderReference();
    const payload: Record<string, unknown> = { amount: formatAmount(amount), currency: "TZS", orderReference: reference, phoneNumber: phone };
    if (config.checksumKey) payload.checksum = createChecksum(config.checksumKey, payload);
    let paymentId = existing?.id;
    if(paymentId){await service.from("agent_listing_payments").update({requested_amount:amount,customer_phone_number:phone,payment_status:"pending"}).eq("id",paymentId).neq("payment_status","paid");}
    if (!paymentId) {
      const { data, error } = await service.from("agent_listing_payments").insert({ listing_id: listingId, agent_id: agent.id, order_reference: reference, customer_phone_number: phone, requested_amount: amount }).select("id").single();
      if (error) throw new Error(error.message); paymentId = data.id;
    }
    const access = await fetchClickPesaToken(config);
    const preview = await previewUssdPushRequest(config, access, payload);
    if (!(preview.activeMethods ?? []).some((m) => (m.status ?? "").toUpperCase() === "AVAILABLE")) throw new ClickPesaRequestError("No mobile-money payment method is available for your agent phone.", 400, preview);
    const initiated = await initiateUssdPushRequest(config, access, payload);
    const status = mapClickPesaStatus(initiated.status);
    await service.from("agent_listing_payments").update({ payment_status: status, provider_payment_id: initiated.id ?? null, provider_channel: preview.sender?.accountProvider ?? initiated.channel ?? null, provider_response: { preview, initiated } }).eq("id", paymentId);
    return json({ success: true, paymentRequired: true, paymentId, paymentStatus: status, amount, currency: "TZS", phoneNumber: phone });
  } catch (error) {
    const status = error instanceof ClickPesaRequestError ? error.status : 500;
    return json({ error: error instanceof Error ? error.message : "Could not start listing payment." }, status);
  }
});
