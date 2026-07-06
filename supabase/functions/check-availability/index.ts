import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const {
    listingId,
    requestedStartAt,
    requestedEndAt,
  } = await request.json();

  if (!listingId) {
    return json({ error: "listingId is required" }, 400);
  }
  if ((requestedStartAt && !requestedEndAt) || (!requestedStartAt && requestedEndAt)) {
    return json(
      { error: "requestedStartAt and requestedEndAt must be provided together" },
      400,
    );
  }
  if (
    requestedStartAt &&
    requestedEndAt &&
    new Date(requestedStartAt).getTime() >= new Date(requestedEndAt).getTime()
  ) {
    return json(
      { error: "requestedEndAt must be after requestedStartAt" },
      400,
    );
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const { data: listing, error: listingError } = await supabase
    .from("listings")
    .select(
      "id, approval_status, status, availability_status, removed_from_market_at, asset_categories!inner(slug), agents!inner(account_status)",
    )
    .eq("id", listingId)
    .single();

  if (listingError || !listing) {
    return json({ error: "Listing not found" }, 404);
  }

  const available =
    listing.approval_status === "approved" &&
    listing.status === "active" &&
    listing.availability_status === "available" &&
    listing.removed_from_market_at === null &&
    listing.agents.account_status === "active";

  const category =
    (listing.asset_categories as Record<string, unknown> | null) ?? {};
  const categorySlug = typeof category.slug === "string" ? category.slug : "";
  const shouldCheckSchedule =
    categorySlug === "apartment" &&
    typeof requestedStartAt === "string" &&
    typeof requestedEndAt === "string" &&
    requestedStartAt.trim().length > 0 &&
    requestedEndAt.trim().length > 0;

  if (!available) {
    return json({
      available: false,
      conflicts: {
        blocks: [],
        bookings: [],
      },
      reason: "Listing is not active on the marketplace",
    });
  }

  if (!shouldCheckSchedule) {
    return json({
      available: true,
      conflicts: {
        blocks: [],
        bookings: [],
      },
      reason: null,
    });
  }

  const [blocksResult, bookingsResult] = await Promise.all([
    supabase
      .from("availability_blocks")
      .select("id, start_at, end_at, block_reason")
      .eq("listing_id", listingId)
      .lt("start_at", requestedEndAt)
      .gt("end_at", requestedStartAt)
      .order("start_at", { ascending: true }),
    supabase
      .from("booking_requests")
      .select("id, request_reference, booking_status, requested_start_at, requested_end_at")
      .eq("listing_id", listingId)
      .not(
        "booking_status",
        "in",
        "(completed,cancelled,rejected,no_response)",
      )
      .not("requested_start_at", "is", null)
      .not("requested_end_at", "is", null)
      .lt("requested_start_at", requestedEndAt)
      .gt("requested_end_at", requestedStartAt)
      .order("requested_start_at", { ascending: true }),
  ]);

  if (blocksResult.error) {
    return json({ error: blocksResult.error.message }, 500);
  }
  if (bookingsResult.error) {
    return json({ error: bookingsResult.error.message }, 500);
  }

  const blocks = blocksResult.data ?? [];
  const bookings = bookingsResult.data ?? [];
  const scheduleAvailable = blocks.length === 0 && bookings.length === 0;

  return json({
    available: scheduleAvailable,
    conflicts: {
      blocks,
      bookings,
    },
    reason: scheduleAvailable ? null : "The apartment is not available for the selected dates",
  });
});
