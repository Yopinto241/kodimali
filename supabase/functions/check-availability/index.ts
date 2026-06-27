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

  const { listingId } = await request.json();

  if (!listingId) {
    return json({ error: "listingId is required" }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const { data: listing, error: listingError } = await supabase
    .from("listings")
    .select("id, approval_status, status, availability_status, removed_from_market_at, agents!inner(account_status)")
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

  return json({
    available,
    conflicts: {
      blocks: [],
      bookings: [],
    },
    reason: available ? null : "Listing is not active on the marketplace",
  });
});
