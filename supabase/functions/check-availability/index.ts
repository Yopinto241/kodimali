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
    .select("id, category_id")
    .eq("id", listingId)
    .maybeSingle();

  if (listingError) {
    return json({ error: listingError.message }, 500);
  }
  if (!listing) {
    return json({ error: "Listing not found" }, 404);
  }

  const [categoryResult, publicResult] = await Promise.all([
    supabase
      .from("asset_categories")
      .select("slug")
      .eq("id", listing.category_id)
      .maybeSingle(),
    supabase.rpc("is_listing_public", { p_listing_id: listingId }),
  ]);

  if (categoryResult.error) {
    return json({ error: categoryResult.error.message }, 500);
  }
  if (publicResult.error) {
    return json({ error: publicResult.error.message }, 500);
  }

  const available = publicResult.data === true;

  const categorySlug = categoryResult.data?.slug ?? "";
  const shouldCheckSchedule =
    new Set([
      "house",
      "apartment",
      "car",
      "motorcycle",
      "office",
      "meeting-hall",
      "ceremony-hall",
    ]).has(categorySlug) &&
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

  const availabilityResult = await supabase.rpc(
    "check_listing_period_availability",
    {
      p_listing_id: listingId,
      p_start_at: requestedStartAt,
      p_end_at: requestedEndAt,
    },
  );
  if (availabilityResult.error) {
    return json({ error: availabilityResult.error.message }, 500);
  }
  const result = availabilityResult.data as {
    available?: boolean;
    reason?: string | null;
  } | null;
  const scheduleAvailable = result?.available === true;

  return json({
    available: scheduleAvailable,
    conflicts: {
      blocks: [],
      bookings: [],
    },
    reason: result?.reason ??
      (scheduleAvailable ? null : "The listing is not available for the selected period"),
  });
});
