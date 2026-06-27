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

  const { agentId, bookingRequestId, title, body } = await request.json();
  if (!agentId || !title || !body) {
    return json({ error: "agentId, title, and body are required" }, 400);
  }

  const { data: agent, error: agentError } = await serviceClient
    .from("agents")
    .select("profile_id")
    .eq("id", agentId)
    .single();

  if (agentError || !agent) {
    return json({ error: "Agent not found" }, 404);
  }

  const { data: tokens } = await serviceClient
    .from("device_tokens")
    .select("device_token, platform")
    .eq("user_id", agent.profile_id);

  await serviceClient.from("notifications").insert({
    user_id: agent.profile_id,
    booking_request_id: bookingRequestId ?? null,
    type: "booking_created",
    title,
    body,
    payload: {
      bookingId: bookingRequestId ?? null,
    },
  });

  return json({
    success: true,
    registeredDevices: tokens?.length ?? 0,
    delivery: "pending_fcm_bridge",
  });
});
