import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const normalizePhone = (value: string) => value.replace(/[^\d+]/g, "");
const normalizeEmail = (value: string) => value.trim().toLowerCase();
const allowedKeys = [
  "listingId",
  "customerName",
  "customerPhoneNumber",
  "customerEmail",
  "requestedStartAt",
  "requestedEndAt",
  "guestCount",
  "requestMessage",
  "requestedServiceCodes",
] as const;

function hasOnlyAllowedKeys(payload: unknown) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return false;
  }
  const keys = Object.keys(payload);
  return keys.every((key) => allowedKeys.includes(key as (typeof allowedKeys)[number]));
}

function readCategorySlug(value: unknown) {
  if (Array.isArray(value)) {
    const first = value[0] as { slug?: unknown } | undefined;
    if (first && typeof first.slug === "string") {
      return first.slug;
    }
    return "";
  }
  const row = value as { slug?: unknown } | null;
  if (row && typeof row.slug === "string") {
    return row.slug;
  }
  return "";
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const payload = await request.json();
  if (!hasOnlyAllowedKeys(payload)) {
    return json(
      {
        error:
          "Only listingId, customerName, customerPhoneNumber, customerEmail, requestedStartAt, requestedEndAt, guestCount, requestMessage, and requestedServiceCodes are allowed",
      },
      400,
    );
  }

  const {
    listingId,
    customerName,
    customerPhoneNumber,
    customerEmail,
    requestedStartAt,
    requestedEndAt,
    guestCount,
    requestMessage,
    requestedServiceCodes,
  } = payload as Record<string, unknown>;

  const listing_id = typeof listingId === "string" ? listingId.trim() : "";
  const customer_name = typeof customerName === "string" ? customerName.trim() : "";
  const customer_phone_number = typeof customerPhoneNumber === "string"
    ? normalizePhone(customerPhoneNumber)
    : "";
  const customer_email = typeof customerEmail === "string"
    ? normalizeEmail(customerEmail)
    : "";
  const requested_start_at = typeof requestedStartAt === "string"
    ? requestedStartAt.trim()
    : "";
  const requested_end_at = typeof requestedEndAt === "string"
    ? requestedEndAt.trim()
    : "";
  const guest_count = typeof guestCount === "number" && Number.isFinite(guestCount)
    ? Math.trunc(guestCount)
    : typeof guestCount === "string" && guestCount.trim().length > 0
    ? Number.parseInt(guestCount.trim(), 10)
    : null;
  const request_message = typeof requestMessage === "string"
    ? requestMessage.trim()
    : "";
  const requested_service_codes = Array.isArray(requestedServiceCodes)
    ? requestedServiceCodes
      .filter((value): value is string => typeof value === "string")
      .map((value) => value.trim())
      .filter((value) => value.length > 0)
    : [];

  if (!listing_id || customer_name.length < 2) {
    return json(
      { error: "listingId and customerName are required" },
      400,
    );
  }
  if (!customer_phone_number && !customer_email) {
    return json({ error: "Provide at least an email address or phone number" }, 400);
  }
  if (customer_email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(customer_email)) {
    return json({ error: "Enter a valid email address" }, 400);
  }
  if (customer_phone_number && customer_phone_number.length < 8) {
    return json({ error: "Enter a valid phone number" }, 400);
  }
  if (guest_count !== null && guest_count < 1) {
    return json({ error: "Guest count must be at least 1" }, 400);
  }

  const { data: listing, error: listingError } = await supabase
    .from("listings")
    .select("id, agent_id, title, asset_categories!inner(slug)")
    .eq("id", listing_id)
    .single();

  if (listingError || !listing) {
    return json({ error: "Listing not found" }, 404);
  }

  const categorySlug = readCategorySlug(listing.asset_categories);
  const isApartment = categorySlug === "apartment";

  if (isApartment && !customer_email) {
    return json({ error: "Apartment bookings require an email address" }, 400);
  }
  if (isApartment && (!requested_start_at || !requested_end_at)) {
    return json(
      { error: "Apartment bookings require check-in and check-out dates" },
      400,
    );
  }

  const { data: isPublic, error: publicRuleError } = await supabase.rpc(
    "is_listing_public",
    { p_listing_id: listing_id },
  );

  if (publicRuleError) {
    return json({ error: publicRuleError.message }, 500);
  }

  if (isPublic !== true) {
    return json({ error: "Listing is not accepting public requests" }, 400);
  }

  const duplicateWindowStart = new Date(Date.now() - 10 * 60 * 1000).toISOString();
  let duplicateQuery = supabase
    .from("booking_requests")
    .select("id, request_reference")
    .eq("listing_id", listing_id)
    .gte("created_at", duplicateWindowStart)
    .order("created_at", { ascending: false })
    .limit(1);

  const duplicateFilters: string[] = [];
  if (customer_phone_number) {
    duplicateFilters.push(`customer_phone_number.eq.${customer_phone_number}`);
  }
  if (customer_email) {
    duplicateFilters.push(`customer_email.eq.${customer_email}`);
  }
  if (duplicateFilters.length > 0) {
    duplicateQuery = duplicateQuery.or(duplicateFilters.join(","));
  }

  const { data: recentDuplicates, error: duplicateError } = await duplicateQuery;

  if (duplicateError) {
    return json({ error: duplicateError.message }, 500);
  }

  if ((recentDuplicates ?? []).length > 0) {
    return json(
      {
        error: "A recent request from this contact already exists for this listing",
        requestReference: recentDuplicates[0]?.request_reference ?? null,
      },
      409,
    );
  }

  const { data: booking, error: bookingError } = await supabase
    .from("booking_requests")
    .insert({
      listing_id,
      customer_id: null,
      customer_name,
      customer_phone_number: customer_phone_number || null,
      customer_email: customer_email || null,
      requested_start_at: requested_start_at || null,
      requested_end_at: requested_end_at || null,
      guest_count,
      request_message: request_message || null,
      requested_service_codes,
      booking_status: "new",
      agent_id: listing.agent_id,
    })
    .select("id, request_reference, booking_status, agent_id")
    .single();

  if (bookingError || !booking) {
    return json({ error: bookingError?.message ?? "Could not create request" }, 500);
  }

  await supabase.from("booking_status_history").insert({
    booking_request_id: booking.id,
    status: "new",
    changed_by: null,
    reason: "Public guest inquiry created",
  });

  return json({
    success: true,
    bookingId: booking.id,
    requestReference: booking.request_reference,
    status: booking.booking_status,
  });
});
