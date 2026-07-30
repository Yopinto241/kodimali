import { createClient } from "npm:@supabase/supabase-js@2";

import {
  json,
  mapClickPesaStatus,
  readClickPesaConfig,
  validateChecksum,
} from "../_shared/clickpesa.ts";

type JsonRecord = Record<string, unknown>;

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  try {
    const payload = await request.json();
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      return json({ error: "Invalid webhook payload" }, 400);
    }

    const config = readClickPesaConfig();
    const record = payload as JsonRecord;
    if (config.checksumKey && typeof record.checksum === "string") {
      const valid = validateChecksum(config.checksumKey, record);
      if (!valid) {
        return json({ error: "Invalid checksum" }, 401);
      }
    }

    const eventName = typeof record.event === "string"
      ? record.event.toUpperCase()
      : "";
    const data = record.data && typeof record.data === "object" &&
        !Array.isArray(record.data)
      ? record.data as JsonRecord
      : {};
    const orderReference = typeof data.orderReference === "string"
      ? data.orderReference.trim()
      : "";

    if (!orderReference) {
      return json({ received: true, ignored: true });
    }

    const { data: contactPayment } = await supabase
      .from("listing_contact_payments")
      .select("id")
      .eq("order_reference", orderReference)
      .maybeSingle();
    const { data: agentListingPayment } = contactPayment ? { data: null } : await supabase
      .from("agent_listing_payments")
      .select("id")
      .eq("order_reference", orderReference)
      .maybeSingle();
    const { data: chatPayment } = contactPayment || agentListingPayment ? { data: null } : await supabase
      .from("listing_chat_payments")
      .select("id")
      .eq("order_reference", orderReference)
      .maybeSingle();
    const payment = contactPayment ?? agentListingPayment ?? chatPayment;
    const paymentTable = contactPayment
      ? "listing_contact_payments"
      : agentListingPayment ? "agent_listing_payments" : "listing_chat_payments";

    const providerEventId = typeof record.eventId === "string"
      ? record.eventId.trim()
      : typeof record.id === "string"
      ? record.id.trim()
      : null;
    const { data: eventRow, error: eventInsertError } = await supabase
      .from("payment_provider_events")
      .insert({
        // payment_provider_events currently references contact payments only.
        payment_id: contactPayment?.id ?? null,
        order_reference: orderReference,
        provider_event_id: providerEventId || null,
        event_type: eventName || "UNKNOWN",
        provider_status: typeof data.status === "string" ? data.status : null,
        payload,
        processing_status: payment?.id ? "received" : "ignored",
        processed_at: payment?.id ? null : new Date().toISOString(),
      })
      .select("id")
      .maybeSingle();

    if (eventInsertError && eventInsertError.code !== "23505") {
      return json({ error: "Could not record webhook event" }, 500);
    }

    if (!payment?.id) {
      return json({ received: true, ignored: true });
    }

    let paymentStatus = mapClickPesaStatus(
      typeof data.status === "string" ? data.status : undefined,
    );
    if (eventName === "PAYMENT RECEIVED") {
      paymentStatus = "paid";
    } else if (eventName === "PAYMENT FAILED") {
      paymentStatus = "failed";
    }

    const updatePayload: Record<string, unknown> = {
      payment_status: paymentStatus,
      provider_payment_id: typeof data.id === "string" ? data.id : null,
      provider_payment_reference: typeof data.paymentReference === "string"
        ? data.paymentReference
        : null,
      provider_channel: typeof data.channel === "string" ? data.channel : null,
      status_message: typeof data.message === "string" ? data.message : null,
      webhook_payload: payload,
      webhook_received_at: new Date().toISOString(),
      reconciliation_status: paymentStatus === "paid"
        ? "pending"
        : paymentStatus === "failed"
        ? "not_required"
        : "pending",
      next_reconcile_at: paymentStatus === "paid"
        ? new Date().toISOString()
        : null,
      paid_at: paymentStatus === "paid" ? new Date().toISOString() : null,
      failed_at: paymentStatus === "failed" ? new Date().toISOString() : null,
      updated_at: new Date().toISOString(),
    };

    const { error: paymentUpdateError } = await supabase
      .from(paymentTable)
      .update(updatePayload)
      .eq("id", payment.id);

    if (eventRow?.id) {
      await supabase
        .from("payment_provider_events")
        .update({
          processing_status: paymentUpdateError ? "failed" : "processed",
          processing_error: paymentUpdateError?.message ?? null,
          processed_at: new Date().toISOString(),
        })
        .eq("id", eventRow.id);
    }

    if (paymentUpdateError) {
      return json({ error: "Could not apply webhook event" }, 500);
    }

    return json({ received: true });
  } catch (error) {
    return json({
      error: error instanceof Error && error.message.trim().length > 0
        ? error.message
        : "Webhook processing failed",
    }, 500);
  }
});
