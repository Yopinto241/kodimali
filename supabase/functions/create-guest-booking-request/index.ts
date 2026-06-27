import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const normalizePhone = (value: string) => value.replace(/[^\d+]/g, "");
const allowedKeys = ["listing_id", "customer_name", "customer_phone_number"] as const;

function hasOnlyAllowedKeys(payload: unknown) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return false;
  }
  const keys = Object.keys(payload);
  return keys.every((key) => allowedKeys.includes(key as (typeof allowedKeys)[number])) &&
    keys.length === allowedKeys.length;
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
      { error: "Only listing_id, customer_name, and customer_phone_number are allowed" },
      400,
    );
  }

  const { listing_id, customer_name, customer_phone_number } = payload as Record<string, unknown>;

  const listingId = typeof listing_id === "string" ? listing_id.trim() : "";
  const customerName = typeof customer_name === "string" ? customer_name.trim() : "";
  const customerPhoneNumber = typeof customer_phone_number === "string"
    ? normalizePhone(customer_phone_number)
    : "";

  if (!listingId || customerName.length < 2 || customerPhoneNumber.length < 8) {
    return json(
      { error: "listing_id, customer_name, and customer_phone_number are required" },
      400,
    );
  }

  const { data: listing, error: listingError } = await supabase
    .from("listings")
    .select("id")
    .eq("id", listingId)
    .single();

  if (listingError || !listing) {
    return json({ error: "Listing not found" }, 404);
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
  const { data: recentDuplicates, error: duplicateError } = await supabase
    .from("booking_requests")
    .select("id, request_reference")
    .eq("listing_id", listingId)
    .eq("customer_phone_number", customerPhoneNumber)
    .gte("created_at", duplicateWindowStart)
    .order("created_at", { ascending: false })
    .limit(1);

  if (duplicateError) {
    return json({ error: duplicateError.message }, 500);
  }

  if ((recentDuplicates ?? []).length > 0) {
    return json(
      {
        error: "A recent request from this phone number already exists for this listing",
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
      customer_phone_number: customerPhoneNumber,
    })
    .select("id, request_reference, booking_status")
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
