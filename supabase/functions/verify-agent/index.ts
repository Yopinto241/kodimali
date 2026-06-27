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

  const { agentId, accountStatus, verificationStatus, moderationNote, deactivationReason } =
    await request.json();

  if (!agentId || !accountStatus) {
    return json({ error: "agentId and accountStatus are required" }, 400);
  }

  const now = new Date().toISOString();
  const updates: Record<string, unknown> = {
    account_status: accountStatus,
    activated_at: accountStatus === "active" ? now : null,
    deactivated_at: accountStatus === "active" ? null : now,
    deactivation_reason: accountStatus === "active" ? null : (deactivationReason ?? null),
    admin_notes: moderationNote ?? null,
  };

  if (typeof verificationStatus === "string" && verificationStatus.length > 0) {
    updates.verification_status = verificationStatus;
    updates.verified_at = verificationStatus === "approved" ? now : null;
  }

  const { data: agent, error: updateError } = await serviceClient
    .from("agents")
    .update(updates)
    .eq("id", agentId)
    .select("id, profile_id")
    .single();

  if (updateError || !agent) {
    return json({ error: updateError?.message ?? "Agent not found" }, 404);
  }

  await serviceClient.from("audit_logs").insert({
    actor_id: user.id,
    action: "update_agent_account_status",
    target_table: "agents",
    target_id: agentId,
    metadata: {
      accountStatus,
      verificationStatus: verificationStatus ?? null,
      moderationNote: moderationNote ?? null,
      deactivationReason: deactivationReason ?? null,
    },
  });

  await serviceClient.from("notifications").insert({
    user_id: agent.profile_id,
    type: "agent_account_updated",
    title: "Agent account status updated",
    body: `Your account status is now ${accountStatus}.`,
    payload: {
      agentId,
      accountStatus,
      verificationStatus: verificationStatus ?? null,
    },
  });

  return json({
    success: true,
    agentId,
    accountStatus,
    verificationStatus: verificationStatus ?? null,
  });
});
