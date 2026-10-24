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

  // Execute with the verified caller JWT so the database function can enforce
  // admin identity through auth.uid(); table writes remain SECURITY DEFINER.
  const { data: result, error: updateError } = await userClient.rpc(
    "admin_set_listing_marketplace_status",
    {
      p_listing_id: listingId,
      p_status: status,
      p_availability_status: availabilityStatus ?? (removedReason === "rented" ? "rented" : "available"),
      p_removed_reason: removedReason ?? null,
      p_moderation_note: moderationNote ?? null,
    },
  );

  if (updateError || !result) {
    return json({ error: updateError?.message ?? "Listing not found" }, 404);
  }

  const { data: listing } = await serviceClient
    .from("listings")
    .select("id, agent_id")
    .eq("id", listingId)
    .single();

  const { data: agent } = await serviceClient
    .from("agents")
    .select("profile_id")
    .eq("id", listing?.agent_id ?? "")
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

  return json(result);
});
