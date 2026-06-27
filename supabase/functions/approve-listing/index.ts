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

  const authorization = request.headers.get("Authorization");
  if (!authorization) {
    return json({ error: "Missing Authorization header" }, 401);
  }

  const jwt = authorization.replace("Bearer ", "");
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const userClient = createClient(supabaseUrl, serviceRoleKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  const serviceClient = createClient(supabaseUrl, serviceRoleKey);

  const {
    data: { user },
  } = await userClient.auth.getUser(jwt);

  if (!user) {
    return json({ error: "Unauthorized" }, 401);
  }

  const { data: role } = await serviceClient
    .from("user_roles")
    .select("role")
    .eq("profile_id", user.id)
    .eq("role", "admin")
    .maybeSingle();

  if (role?.role !== "admin") {
    return json({ error: "Forbidden" }, 403);
  }

  const { listingId, status, availabilityStatus, removedReason, moderationNote } =
    await request.json();

  if (!listingId || !status) {
    return json({ error: "listingId and status are required" }, 400);
  }

  const isRemoved = status !== "active" || removedReason != null;
  const { data: listing, error: updateError } = await serviceClient
    .from("listings")
    .update({
      approval_status: "approved",
      status,
      availability_status: availabilityStatus ?? (removedReason === "rented" ? "rented" : "available"),
      published_at: status === "active" ? new Date().toISOString() : null,
      removed_from_market_at: isRemoved ? new Date().toISOString() : null,
      removed_reason: isRemoved ? (removedReason ?? "admin_removed") : null,
    })
    .eq("id", listingId)
    .select("id, agent_id")
    .single();

  if (updateError || !listing) {
    return json({ error: updateError?.message ?? "Listing not found" }, 404);
  }

  await serviceClient.from("audit_logs").insert({
    actor_id: user.id,
    action: "update_listing_marketplace_status",
    target_table: "listings",
    target_id: listingId,
    metadata: {
      status,
      availabilityStatus: availabilityStatus ?? null,
      removedReason: removedReason ?? null,
      moderationNote: moderationNote ?? null,
    },
  });

  const { data: agent } = await serviceClient
    .from("agents")
    .select("profile_id")
    .eq("id", listing.agent_id)
    .single();

  if (agent?.profile_id) {
    await serviceClient.from("notifications").insert({
      user_id: agent.profile_id,
      type: "listing_approved",
      title: "Listing marketplace status updated",
      body: `Your listing is now ${status}.`,
      payload: {
        listingId,
        status,
        removedReason: removedReason ?? null,
      },
    });
  }

  return json({ success: true, listingId, status });
});
