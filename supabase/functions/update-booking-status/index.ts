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

  const { bookingRequestId, nextStatus, reason } = await request.json();
  if (!bookingRequestId || !nextStatus) {
    return json({ error: "bookingRequestId and nextStatus are required" }, 400);
  }

  const { data: booking, error: bookingError } = await serviceClient
    .from("booking_requests")
    .select("id, customer_id, agent_id, listing_id, requested_start_at, requested_end_at, first_agent_response_at")
    .eq("id", bookingRequestId)
    .single();

  if (bookingError || !booking) {
    return json({ error: "Booking request not found" }, 404);
  }

  const [{ data: agent }, { data: adminRole }] = await Promise.all([
    serviceClient.from("agents").select("id").eq("profile_id", user.id).maybeSingle(),
    serviceClient
      .from("user_roles")
      .select("role")
      .eq("profile_id", user.id)
      .eq("role", "admin")
      .maybeSingle(),
  ]);

  const canManage = booking.agent_id === agent?.id || adminRole?.role === "admin";
  if (!canManage) {
    return json({ error: "Forbidden" }, 403);
  }

  const updatePayload: Record<string, string> = {
    booking_status: nextStatus,
  };

  if (!booking.first_agent_response_at && adminRole?.role !== "admin") {
    updatePayload.first_agent_response_at = new Date().toISOString();
  }

  const { error: updateError } = await serviceClient
    .from("booking_requests")
    .update(updatePayload)
    .eq("id", bookingRequestId);

  if (updateError) {
    return json({ error: updateError.message }, 500);
  }

  await serviceClient.from("booking_status_history").insert({
    booking_request_id: bookingRequestId,
    status: nextStatus,
    changed_by: user.id,
    reason: reason ?? "Status updated by agent or admin",
  });

  if (booking.customer_id) {
    await serviceClient.from("notifications").insert({
      user_id: booking.customer_id,
      booking_request_id: bookingRequestId,
      type: "booking_status_changed",
      title: "Booking status updated",
      body: `Your request is now ${nextStatus}.`,
      payload: {
        bookingId: bookingRequestId,
        status: nextStatus,
      },
    });
  }

  return json({ success: true, bookingRequestId, nextStatus });
});
