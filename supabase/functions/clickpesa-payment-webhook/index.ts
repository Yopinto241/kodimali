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
      paid_at: paymentStatus === "paid" ? new Date().toISOString() : null,
      failed_at: paymentStatus === "failed" ? new Date().toISOString() : null,
      updated_at: new Date().toISOString(),
    };

    await supabase
      .from("listing_contact_payments")
      .update(updatePayload)
      .eq("order_reference", orderReference);

    return json({ received: true });
  } catch (error) {
    return json({
      error: error instanceof Error && error.message.trim().length > 0
        ? error.message
        : "Webhook processing failed",
    }, 500);
  }
});
