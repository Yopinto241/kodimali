import { createClient } from "npm:@supabase/supabase-js@2";

import {
  ClickPesaRequestError,
  createChecksum,
  fetchClickPesaToken,
  formatAmount,
  initiateUssdPushRequest,
  json,
  mapClickPesaStatus,
  normalizePhoneNumber,
  previewUssdPushRequest,
  readClickPesaConfig,
} from "../_shared/clickpesa.ts";

const CONTACT_PRICE_STANDARD_TZS = 500;
const CONTACT_PRICE_PREMIUM_TZS = 1000;
const CONTACT_PRICE_COLLECTION_MIN_TZS = 908;
const premiumCategorySlugs = new Set<string>([
  "car",
  "office",
  "meeting-hall",
  "meeting_hall",
  "ceremony-hall",
  "ceremony_hall",
  "farms",
  "farm",
]);

type RpcClient = {
  rpc: (
    fn: string,
    params?: Record<string, unknown>,
  ) => PromiseLike<{
    data: unknown;
    error: { code?: string; message: string } | null;
  }>;
};

function friendlyErrorMessage(error: unknown): string {
  if (error instanceof ClickPesaRequestError) {
    return error.message;
  }
  if (error instanceof Error && error.message.trim().length > 0) {
    return error.message;
  }
  return "We could not start the payment right now. Please try again shortly.";
}

function readAmountEnv(
  envKey: string,
  fallback: number,
): number {
  const raw = (Deno.env.get(envKey) ?? "").trim();
  if (!raw) {
    return fallback;
  }
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function paymentAmountTzs(categorySlug: string): number {
  const normalizedSlug = categorySlug.trim().toLowerCase();
  const minimumCollectionAmount = readAmountEnv(
    "CLICKPESA_COLLECTION_MIN_TZS",
    CONTACT_PRICE_COLLECTION_MIN_TZS,
  );
  if (premiumCategorySlugs.has(normalizedSlug)) {
    return Math.max(
      readAmountEnv(
      "CLICKPESA_CONTACT_PRICE_PREMIUM_TZS",
      CONTACT_PRICE_PREMIUM_TZS,
      ),
      minimumCollectionAmount,
    );
  }
  return Math.max(
    readAmountEnv(
      "CLICKPESA_CONTACT_PRICE_STANDARD_TZS",
      CONTACT_PRICE_STANDARD_TZS,
    ),
    minimumCollectionAmount,
  );
}

function createOrderReference(): string {
  const raw = crypto.randomUUID().replace(/-/g, "").toUpperCase();
  return `CT${raw.slice(0, 18)}`;
}

function contactPaymentConfig() {
  return readClickPesaConfig({
    clientIdEnv: "CLICKPESA_COLLECTION_CLIENT_ID",
    apiKeyEnv: "CLICKPESA_COLLECTION_API_KEY",
    checksumKeyEnv: "CLICKPESA_COLLECTION_CHECKSUM_KEY",
  });
}

async function contactPaymentsEnabled(
  supabase: RpcClient,
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
    const authorization = request.headers.get("Authorization");
    let customerId: string | null = null;
    if (authorization?.startsWith("Bearer ")) {
      const token = authorization.slice("Bearer ".length).trim();
      const {
        data: { user },
      } = await supabase.auth.getUser(token);
      customerId = user?.id ?? null;
    }

    const body = await request.json();
    const listingId = typeof body?.listing_id === "string"
      ? body.listing_id.trim()
      : "";
    const customerName = typeof body?.customer_name === "string"
      ? body.customer_name.trim()
      : "";
    const customerPhoneNumber = normalizePhoneNumber(
      typeof body?.customer_phone_number === "string"
        ? body.customer_phone_number
        : "",
    );
    const customerEmail = typeof body?.customer_email === "string"
      ? body.customer_email.trim()
      : "";

    if (!listingId) {
      return json({ error: "Choose a listing first." }, 400);
    }
    if (customerName.length < 2) {
      return json({ error: "Enter your full name before continuing." }, 400);
    }
    if (customerPhoneNumber.length < 12) {
      return json(
        { error: "Enter a valid phone number with the correct country code." },
        400,
      );
    }

    const { data: listing, error: listingError } = await supabase
      .from("listings")
      .select("id, title, agent_id, asset_categories!inner(slug)")
      .eq("id", listingId)
      .single();

    if (listingError || !listing) {
      return json(
        { error: "This listing could not be found anymore." },
        404,
      );
    }

    const { data: isPublic, error: isPublicError } = await supabase.rpc(
      "is_listing_public",
      { p_listing_id: listingId },
    );
    if (isPublicError) {
      throw new Error(isPublicError.message);
    }
    if (isPublic !== true) {
      return json(
        {
          error:
            "This listing is not accepting public contact payments right now.",
        },
        400,
      );
    }

    const { data: agent, error: agentError } = await supabase
      .from("agents")
      .select("id, phone_number, display_name, business_name")
      .eq("id", listing.agent_id)
      .single();

    if (agentError || !agent || !agent.phone_number) {
      return json(
        {
          error:
            "The agent contact is not available yet, so payment cannot continue.",
        },
        400,
      );
    }

    const paymentsEnabled = await contactPaymentsEnabled(supabase);
    if (!paymentsEnabled) {
      const displayName = (agent.display_name as string | null)?.trim() ||
        (agent.business_name as string | null)?.trim() ||
        "Agent";
      return json({
        success: true,
        paymentRequired: false,
        paymentStatus: "paid",
        message:
          "Payments are off right now. The agent phone number is available.",
        phoneNumber: agent.phone_number,
        agentDisplayName: displayName,
      });
    }

    const categoryRelation = listing.asset_categories as
      | Record<string, unknown>
      | Record<string, unknown>[]
      | null;
    const category = Array.isArray(categoryRelation)
      ? categoryRelation[0] ?? {}
      : categoryRelation ?? {};
    const categorySlug = typeof category["slug"] === "string"
      ? category["slug"] as string
      : "";
    const config = contactPaymentConfig();
    const amount = paymentAmountTzs(categorySlug);
    const orderReference = createOrderReference();
    const accessToken = crypto.randomUUID();
    const previewPayload: Record<string, unknown> = {
      amount: formatAmount(amount),
      orderReference,
      currency: "TZS",
      phoneNumber: customerPhoneNumber,
      fetchSenderDetails: true,
    };
    if (config.checksumKey) {
      previewPayload.checksum = createChecksum(config.checksumKey, previewPayload);
    }

    const { data: paymentRow, error: paymentInsertError } = await supabase
      .from("listing_contact_payments")
      .insert({
        listing_id: listingId,
        agent_id: agent.id,
        customer_id: customerId,
        order_reference: orderReference,
        access_token: accessToken,
        requested_amount: amount,
        requested_currency: "TZS",
        customer_name: customerName,
        customer_phone_number: customerPhoneNumber,
        customer_email: customerEmail || null,
        checkout_payload: previewPayload,
      })
      .select("id")
      .single();

    if (paymentInsertError || !paymentRow) {
      throw new Error(
        paymentInsertError?.message ?? "Could not save the pending payment.",
      );
    }

    try {
      const clickPesaToken = await fetchClickPesaToken(config);
      const preview = await previewUssdPushRequest(
        config,
        clickPesaToken,
        previewPayload,
      );

      const availableMethods = (preview.activeMethods ?? []).filter((method) =>
        (method.status ?? "").toUpperCase() === "AVAILABLE"
      );
      if (availableMethods.length === 0) {
        throw new ClickPesaRequestError(
          "This phone number does not have an available mobile money payment method right now.",
          400,
          preview,
        );
      }

      const initiatePayload: Record<string, unknown> = {
        amount: formatAmount(amount),
        currency: "TZS",
        orderReference,
        phoneNumber: customerPhoneNumber,
      };
      if (config.checksumKey) {
        initiatePayload.checksum = createChecksum(
          config.checksumKey,
          initiatePayload,
        );
      }

      const initiated = await initiateUssdPushRequest(
        config,
        clickPesaToken,
        initiatePayload,
      );
      const mappedStatus = mapClickPesaStatus(initiated.status);
      const detectedChannel =
        (preview.sender?.accountProvider ?? initiated.channel ?? "").trim();
      const senderName = (preview.sender?.accountName ?? "").trim();

      await supabase
        .from("listing_contact_payments")
        .update({
          provider_client_id: typeof initiated.clientId === "string"
            ? initiated.clientId
            : null,
          provider_payment_id: typeof initiated.id === "string"
            ? initiated.id
            : null,
          provider_channel: detectedChannel.length === 0
            ? null
            : detectedChannel,
          provider_response: {
            preview,
            initiated,
          },
          payment_status: mappedStatus,
          status_message: mappedStatus === "failed"
            ? "The payment request could not be sent to this phone number."
            : null,
        })
        .eq("id", paymentRow.id);

      return json({
        success: true,
        paymentId: paymentRow.id,
        accessToken,
        orderReference,
        amount,
        currency: "TZS",
        paymentMethod: detectedChannel,
        senderName,
        paymentStatus: mappedStatus,
        message:
          "Payment request sent. Confirm it on your phone to unlock the agent number.",
      });
    } catch (error) {
      await supabase
        .from("listing_contact_payments")
        .update({
          payment_status: "failed",
          status_message: friendlyErrorMessage(error),
          failed_at: new Date().toISOString(),
        })
        .eq("id", paymentRow.id);
      throw error;
    }
  } catch (error) {
    const message = friendlyErrorMessage(error);
    const status = error instanceof ClickPesaRequestError ? error.status : 500;
    return json({ error: message }, status);
  }
});
