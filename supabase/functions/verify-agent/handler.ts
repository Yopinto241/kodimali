import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

export async function handleRequest(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
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

  const { data: allowed, error: permissionError } = await userClient.rpc("has_admin_permission", { p_permission: "agents.manage" });
  if (permissionError || allowed !== true) {
    return json({ error: "Agent management access required" }, 403);
  }

  const { agentId, accountStatus, verificationStatus, moderationNote, deactivationReason } =
    await request.json();

  if (!agentId || !accountStatus) {
    return json({ error: "agentId and accountStatus are required" }, 400);
  }

  const { data: manageable, error: scopeError } = await userClient.rpc("can_manage_supervised_agent", { p_agent_id: agentId });
  if (scopeError || manageable !== true) return json({ error: "This agent is not assigned to your team" }, 403);
  const { data: scope, error: contextError } = await userClient.rpc("get_my_supervisor_context");
  if (contextError || !scope) return json({ error: "Could not verify supervisor access" }, 403);

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

  let updateQuery = serviceClient
    .from("agents")
    .update(updates)
    .eq("id", agentId);
  if (scope.scoped) updateQuery = updateQuery.eq("supervisor_id", user.id);
  const { data: agent, error: updateError } = await updateQuery.select("id, profile_id").single();

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
}
