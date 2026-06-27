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

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const { bookingRequestId } = await request.json();
  if (!bookingRequestId) {
    return json({ error: "bookingRequestId is required" }, 400);
  }

  const { data: booking, error: bookingError } = await serviceClient
    .from("booking_requests")
    .select("id, customer_id, agent_id, booking_status, agent_response_due_at")
    .eq("id", bookingRequestId)
    .single();

  if (bookingError || !booking) {
    return json({ error: "Booking request not found" }, 404);
  }

  if (
    booking.booking_status !== "new" &&
    booking.booking_status !== "checking_availability"
  ) {
    return json({ skipped: true, reason: "Booking already progressed" });
  }

  if (!booking.agent_response_due_at || new Date(booking.agent_response_due_at) > new Date()) {
    return json({ skipped: true, reason: "Response SLA not yet breached" });
  }

  const { error: updateError } = await serviceClient
    .from("booking_requests")
    .update({ booking_status: "agent_delayed" })
    .eq("id", bookingRequestId);

  if (updateError) {
    return json({ error: updateError.message }, 500);
  }

  await serviceClient.from("booking_status_history").insert({
    booking_request_id: bookingRequestId,
    status: "agent_delayed",
    reason: "Agent did not respond within 30 minutes",
  });

  const { data: adminProfiles } = await serviceClient
    .from("user_roles")
    .select("profile_id")
    .eq("role", "admin");

  if (adminProfiles?.length) {
    await serviceClient.from("notifications").insert(
      adminProfiles.map((admin) => ({
        user_id: admin.profile_id,
        booking_request_id: bookingRequestId,
        type: "agent_delayed",
        title: "Agent delayed response",
        body: "A booking request has crossed the 30-minute response threshold.",
        payload: {
          bookingId: bookingRequestId,
          agentId: booking.agent_id,
        },
      })),
    );
  }

  return json({ success: true, bookingRequestId, status: "agent_delayed" });
});
