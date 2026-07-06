import { createClient } from "npm:@supabase/supabase-js@2";

import {
  ClickPesaRequestError,
  fetchClickPesaToken,
  json,
  mapClickPesaStatus,
  queryPaymentStatus,
  readClickPesaConfig,
} from "../_shared/clickpesa.ts";

function friendlyMessage(status: string, paymentMessage: string | null): string {
  switch (status) {
    case "paid":
      return "Payment confirmed. The agent phone number is now available.";
    case "failed":
      return paymentMessage?.trim() ||
        "The payment did not complete successfully.";
    case "processing":
      return "A payment prompt is already on the phone. Finish it there and we will unlock the number here.";
    default:
      return "We are still waiting for your mobile money confirmation.";
  }
}

function contactPaymentConfig() {
  return readClickPesaConfig({
    clientIdEnv: "CLICKPESA_COLLECTION_CLIENT_ID",
    apiKeyEnv: "CLICKPESA_COLLECTION_API_KEY",
    checksumKeyEnv: "CLICKPESA_COLLECTION_CHECKSUM_KEY",
  });
}

async function contactPaymentsEnabled(
  supabase: ReturnType<typeof createClient>,
): Promise<boolean> {
  const { data, error } = await supabase.rpc("contact_payments_enabled");
  if (error) {
    if (
      error.code === "PGRST202" ||
      error.message.includes("schema cache") ||
      error.message.includes("Could not find the function")
    ) {
      return true;
    }
    throw new Error(error.message);
  }
  return data !== false;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  try {
    const body = await request.json();
    const paymentId = typeof body?.payment_id === "string"
      ? body.payment_id.trim()
      : "";
    const accessToken = typeof body?.access_token === "string"
      ? body.access_token.trim()
      : "";

    if (!paymentId || !accessToken) {
      return json(
        { error: "The payment session is missing. Start the payment again." },
        400,
      );
    }

    const { data: payment, error: paymentError } = await supabase
      .from("listing_contact_payments")
      .select(
        "id, listing_id, agent_id, order_reference, access_token, payment_status, provider_payment_id, provider_payment_reference, status_message",
      )
      .eq("id", paymentId)
      .eq("access_token", accessToken)
      .single();

    if (paymentError || !payment) {
      return json(
        {
          error:
            "This payment session was not found. Start a new payment to continue.",
        },
        404,
      );
    }

    const { data: agent, error: agentError } = await supabase
      .from("agents")
      .select("id, phone_number, display_name, business_name")
      .eq("id", payment.agent_id)
      .single();

    if (agentError || !agent) {
      return json(
        {
          error:
            "The agent contact is no longer available. Please try a different listing.",
        },
        400,
      );
    }

    let mappedStatus = payment.payment_status as string;
    let paymentMessage = typeof payment.status_message === "string"
      ? payment.status_message
      : null;
    let paymentReference = typeof payment.provider_payment_reference === "string"
      ? payment.provider_payment_reference
      : null;
    let providerPaymentId = typeof payment.provider_payment_id === "string"
      ? payment.provider_payment_id
      : null;
    let providerPayload: Record<string, unknown> | null = null;
    const displayName = (agent.display_name as string | null)?.trim() ||
      (agent.business_name as string | null)?.trim() ||
      "Agent";
    const agentPhoneNumber = typeof agent.phone_number === "string"
      ? agent.phone_number.trim()
      : "";

    if (!agentPhoneNumber) {
      if (mappedStatus === "paid") {
        return json({
          success: false,
          paymentStatus: "paid",
          message:
            "Payment confirmed, but this agent number is not available. Please contact support with your payment reference.",
        });
      }
      return json(
        {
          error:
            "The agent contact is not available, so this payment session cannot unlock a number.",
        },
        400,
      );
    }

    const paymentsEnabled = await contactPaymentsEnabled(supabase);
    if (!paymentsEnabled) {
      await supabase
        .from("listing_contact_payments")
        .update({
          last_status_checked_at: new Date().toISOString(),
          contact_revealed_at: new Date().toISOString(),
        })
        .eq("id", paymentId);

      return json({
        success: true,
        paymentStatus: "paid",
        message:
          "Payments are off right now. The agent phone number is available.",
        phoneNumber: agentPhoneNumber,
        agentDisplayName: displayName,
      });
    }

    if (mappedStatus !== "paid") {
      const config = contactPaymentConfig();
      const clickPesaToken = await fetchClickPesaToken(config);
      const statusPayload = await queryPaymentStatus(
        config,
        clickPesaToken,
        payment.order_reference as string,
      );
      providerPayload = statusPayload
        ? statusPayload as unknown as Record<string, unknown>
        : null;
      mappedStatus = mapClickPesaStatus(statusPayload?.status);
      paymentMessage = statusPayload?.message ?? paymentMessage;
      paymentReference = statusPayload?.paymentReference ?? paymentReference;
      providerPaymentId = statusPayload?.id ?? providerPaymentId;

      await supabase
        .from("listing_contact_payments")
        .update({
          payment_status: mappedStatus,
          provider_payment_id: providerPaymentId,
          provider_payment_reference: paymentReference,
          provider_channel: statusPayload?.channel ?? null,
          status_message: paymentMessage,
          provider_response: providerPayload ?? {},
          paid_at: mappedStatus === "paid" ? new Date().toISOString() : null,
          failed_at: mappedStatus === "failed"
            ? new Date().toISOString()
            : null,
          last_status_checked_at: new Date().toISOString(),
          contact_revealed_at: mappedStatus === "paid"
            ? new Date().toISOString()
            : null,
        })
        .eq("id", paymentId);
    } else {
      await supabase
        .from("listing_contact_payments")
        .update({
          last_status_checked_at: new Date().toISOString(),
          contact_revealed_at: new Date().toISOString(),
        })
        .eq("id", paymentId);
    }

    const message = friendlyMessage(mappedStatus, paymentMessage);
    if (mappedStatus !== "paid") {
      return json({
        success: false,
        paymentStatus: mappedStatus,
        message,
      });
    }

    return json({
      success: true,
      paymentStatus: "paid",
      message,
      phoneNumber: agentPhoneNumber,
      agentDisplayName: displayName,
    });
  } catch (error) {
    const status = error instanceof ClickPesaRequestError ? error.status : 500;
    const message = error instanceof ClickPesaRequestError
      ? error.message
      : error instanceof Error && error.message.trim().length > 0
      ? error.message
      : "We could not verify this payment right now. Please try again shortly.";
    return json({ error: message }, status);
  }
});
