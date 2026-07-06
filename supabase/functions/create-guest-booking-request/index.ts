import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const normalizePhone = (value: string) => value.replace(/[^\d+]/g, "");
const normalizeEmail = (value: string) => value.trim().toLowerCase();
const allowedKeys = [
  "listing_id",
  "customer_name",
  "customer_phone_number",
  "customer_email",
  "requested_start_at",
  "requested_end_at",
  "guest_count",
  "request_message",
  "requested_service_codes",
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
          "Only listing_id, customer_name, customer_phone_number, customer_email, requested_start_at, requested_end_at, guest_count, request_message, and requested_service_codes are allowed",
      },
      400,
    );
  }

  const {
    listing_id,
    customer_name,
    customer_phone_number,
    customer_email,
    requested_start_at,
    requested_end_at,
    guest_count,
    request_message,
    requested_service_codes,
  } = payload as Record<string, unknown>;

  const listingId = typeof listing_id === "string" ? listing_id.trim() : "";
  const customerName = typeof customer_name === "string" ? customer_name.trim() : "";
  const customerPhoneNumber = typeof customer_phone_number === "string"
    ? normalizePhone(customer_phone_number)
    : "";
  const customerEmail = typeof customer_email === "string"
    ? normalizeEmail(customer_email)
    : "";
  const requestedStartAt = typeof requested_start_at === "string"
    ? requested_start_at.trim()
    : "";
  const requestedEndAt = typeof requested_end_at === "string"
    ? requested_end_at.trim()
    : "";
  const guestCount = typeof guest_count === "number" && Number.isFinite(guest_count)
    ? Math.trunc(guest_count)
    : typeof guest_count === "string" && guest_count.trim().length > 0
    ? Number.parseInt(guest_count.trim(), 10)
    : null;
  const requestMessage = typeof request_message === "string"
    ? request_message.trim()
    : "";
  const requestedServiceCodes = Array.isArray(requested_service_codes)
    ? requested_service_codes
      .filter((value): value is string => typeof value === "string")
      .map((value) => value.trim())
      .filter((value) => value.length > 0)
    : [];

  if (!listingId || customerName.length < 2) {
    return json(
      { error: "listing_id and customer_name are required" },
      400,
    );
  }
  if (!customerPhoneNumber && !customerEmail) {
    return json({ error: "Provide at least an email address or phone number" }, 400);
  }
  if (customerEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(customerEmail)) {
    return json({ error: "Enter a valid email address" }, 400);
  }
  if (customerPhoneNumber && customerPhoneNumber.length < 8) {
    return json({ error: "Enter a valid phone number" }, 400);
  }
  if (guestCount !== null && guestCount < 1) {
    return json({ error: "Guest count must be at least 1" }, 400);
  }

  const { data: listing, error: listingError } = await supabase
    .from("listings")
    .select("id, title, asset_categories!inner(slug)")
    .eq("id", listingId)
    .single();

  if (listingError || !listing) {
    return json({ error: "Listing not found" }, 404);
  }

  const categorySlug = readCategorySlug(listing.asset_categories);
  const isApartment = categorySlug === "apartment";

  if (isApartment && !customerEmail) {
    return json({ error: "Apartment bookings require an email address" }, 400);
  }
  if (isApartment && (!requestedStartAt || !requestedEndAt)) {
    return json(
      { error: "Apartment bookings require check-in and check-out dates" },
      400,
    );
  }

  const { data: isPublic, error: publicRuleError } = await supabase.rpc(
    "is_listing_public",
    { p_listing_id: listingId },
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
    .eq("listing_id", listingId)
    .gte("created_at", duplicateWindowStart)
    .order("created_at", { ascending: false })
    .limit(1);

  const duplicateFilters: string[] = [];
  if (customerPhoneNumber) {
    duplicateFilters.push(`customer_phone_number.eq.${customerPhoneNumber}`);
  }
  if (customerEmail) {
    duplicateFilters.push(`customer_email.eq.${customerEmail}`);
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
      listing_id: listingId,
      customer_name: customerName,
      customer_phone_number: customerPhoneNumber || null,
      customer_email: customerEmail || null,
      requested_start_at: requestedStartAt || null,
      requested_end_at: requestedEndAt || null,
      guest_count: guestCount,
      request_message: requestMessage || null,
      requested_service_codes: requestedServiceCodes,
    })
    .select("id, request_reference, booking_status, agent_id")
    .single();

  if (bookingError || !booking) {
    return json({ error: bookingError?.message ?? "Could not create request" }, 500);
  }

  return json({
    success: true,
    bookingId: booking.id,
    requestReference: booking.request_reference,
    request_reference: booking.request_reference,
    status: booking.booking_status,
  });
});
