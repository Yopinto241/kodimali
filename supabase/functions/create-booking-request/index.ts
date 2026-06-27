import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const normalizePhone = (value: string) => value.replace(/[^\d+]/g, "");
const allowedKeys = ["listingId", "customerName", "customerPhoneNumber"] as const;

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
      { error: "Only listingId, customerName, and customerPhoneNumber are allowed" },
      400,
    );
  }

  const { listingId, customerName, customerPhoneNumber } = payload as Record<string, unknown>;

  const listing_id = typeof listingId === "string" ? listingId.trim() : "";
  const customer_name = typeof customerName === "string" ? customerName.trim() : "";
  const customer_phone_number = typeof customerPhoneNumber === "string"
    ? normalizePhone(customerPhoneNumber)
    : "";

  if (!listing_id || customer_name.length < 2 || customer_phone_number.length < 8) {
    return json(
      { error: "listingId, customerName, and customerPhoneNumber are required" },
      400,
    );
  }

  const { data: listing, error: listingError } = await supabase
    .from("listings")
    .select("id, agent_id, title")
    .eq("id", listing_id)
    .single();

  if (listingError || !listing) {
    return json({ error: "Listing not found" }, 404);
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
  const { data: recentDuplicates, error: duplicateError } = await supabase
    .from("booking_requests")
    .select("id, request_reference")
    .eq("listing_id", listing_id)
    .eq("customer_phone_number", customer_phone_number)
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
      listing_id,
      customer_id: null,
      customer_name,
      customer_phone_number,
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

  const { data: agent } = await supabase
    .from("agents")
    .select("profile_id")
    .eq("id", booking.agent_id)
    .single();

  if (agent?.profile_id) {
    await supabase.from("notifications").insert({
      user_id: agent.profile_id,
      booking_request_id: booking.id,
      type: "booking_created",
      title: "New inquiry received",
      body: `${listing.title} | ${customer_name} | ${customer_phone_number}`,
      payload: {
        bookingId: booking.id,
        listingId: listing.id,
        requestReference: booking.request_reference,
      },
    });
  }

  return json({
    success: true,
    bookingId: booking.id,
    requestReference: booking.request_reference,
    status: booking.booking_status,
  });
});
