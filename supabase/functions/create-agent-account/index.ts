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
  const serviceClient = createClient(supabaseUrl, serviceRoleKey);
  const userClient = createClient(supabaseUrl, serviceRoleKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });

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

  const body = await request.json();
  const username = typeof body?.username === "string"
    ? body.username.trim().toLowerCase()
    : "";
  const password = typeof body?.password === "string" ? body.password : "";
  const fullName = typeof body?.full_name === "string"
    ? body.full_name.trim()
    : "";
  const phoneNumber = typeof body?.phone_number === "string"
    ? body.phone_number.trim()
    : "";
  const locationId = typeof body?.location_id === "string"
    ? body.location_id.trim()
    : "";
  const nidaNumber = typeof body?.nida_number === "string"
    ? body.nida_number.trim().toUpperCase()
    : "";
  const preferredLanguage = typeof body?.preferred_language === "string" &&
      body.preferred_language.trim().length > 0
    ? body.preferred_language.trim()
    : "sw";
  const businessName = typeof body?.business_name === "string"
    ? body.business_name.trim()
    : fullName;
  const businessDescription = typeof body?.business_description === "string" &&
      body.business_description.trim().length > 0
    ? body.business_description.trim()
    : null;
  const primaryCategoryId = typeof body?.primary_category_id === "string" &&
      body.primary_category_id.trim().length > 0
    ? body.primary_category_id.trim()
    : null;

  if (password.length < 6) {
    return json({ error: "Password must be at least 6 characters" }, 400);
  }
  if (!username || !/^[a-z0-9_]{3,32}$/.test(username)) {
    return json(
      {
        error:
          "Username is required and must use 3-32 lowercase letters, numbers, or underscores",
      },
      400,
    );
  }
  if (!fullName) {
    return json({ error: "Full name is required" }, 400);
  }
  if (!phoneNumber) {
    return json({ error: "Phone number is required" }, 400);
  }
  if (!locationId) {
    return json({ error: "Location is required" }, 400);
  }
  if (!nidaNumber) {
    return json({ error: "NIDA number is required" }, 400);
  }
  if (!businessName) {
    return json({ error: "Business name is required" }, 400);
  }

  const { data: existingUsername } = await serviceClient
    .from("profiles")
    .select("id")
    .eq("username", username)
    .maybeSingle();

  if (existingUsername?.id) {
    return json({ error: "Username is already in use" }, 400);
  }

  const generatedEmail = `${username}@agent.kodimali.local`;

  const { data: createdUser, error: createUserError } = await serviceClient.auth
    .admin.createUser({
      email: generatedEmail,
      password,
      email_confirm: true,
      user_metadata: {
        full_name: fullName,
        phone_number: phoneNumber,
        preferred_language: preferredLanguage,
        username,
        register_as_agent: true,
        registration_source: "admin_create_agent",
        location_id: locationId,
        nida_number: nidaNumber,
        business_name: businessName,
        business_description: businessDescription,
        primary_category_id: primaryCategoryId,
      },
    });

  if (createUserError || !createdUser.user) {
    return json(
      { error: createUserError?.message ?? "Could not create user" },
      400,
    );
  }

  const profileId = createdUser.user.id;
  const { data: agent, error: agentError } = await serviceClient
    .from("agents")
    .select("id, profile_id, account_status, verification_status")
    .eq("profile_id", profileId)
    .single();

  if (agentError || !agent) {
    return json(
      { error: agentError?.message ?? "Could not create agent" },
      500,
    );
  }

  await serviceClient.from("audit_logs").insert({
    actor_id: user.id,
    action: "admin_created_agent_account",
    target_table: "agents",
    target_id: agent.id,
    metadata: {
      profileId,
      username,
      email: generatedEmail,
      businessName,
      displayName: fullName,
      phoneNumber,
      locationId,
      nidaNumber,
      primaryCategoryId,
      accountStatus: agent.account_status,
      verificationStatus: agent.verification_status,
    },
  });

  return json({
    success: true,
    profileId,
    agentId: agent.id,
    username,
    email: generatedEmail,
    accountStatus: agent.account_status,
    verificationStatus: agent.verification_status,
  });
});
