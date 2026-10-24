import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const normalizeListingMediaPath = (value: unknown) =>
  typeof value === "string" && value.length > 0
    ? value.replace(/^listing-media\//, "")
    : null;

async function getAuthenticatedUser(
  serviceClient: ReturnType<typeof createClient>,
  jwt: string,
) {
  const {
    data: { user },
  } = await serviceClient.auth.getUser(jwt);
  return user;
}

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

  const user = await getAuthenticatedUser(serviceClient, jwt);
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
  const listingId =
    typeof body?.listingId === "string"
      ? body.listingId.trim()
      : typeof body?.listing_id === "string"
      ? body.listing_id.trim()
      : "";
  const confirmDeleteWithInquiries =
    body?.confirm_delete_with_inquiries === true;
  if (!listingId) {
    return json({ error: "listingId or listing_id is required" }, 400);
  }

  const { data, error: deleteError } = await userClient.rpc(
    "admin_permanently_delete_listing",
    {
      p_listing_id: listingId,
      p_confirm_delete_with_inquiries: confirmDeleteWithInquiries,
    },
  );

  if (deleteError || !data) {
    return json({ error: deleteError?.message ?? "Listing could not be deleted" }, 500);
  }

  const result = data as Record<string, unknown>;
  const storagePaths = Array.isArray(result.mediaPaths)
    ? result.mediaPaths.map(normalizeListingMediaPath).filter((value): value is string => value != null)
    : [];

  // Storage is cleaned only after the atomic database deletion succeeds. A
  // transient Storage failure cannot leave a visible listing without media.
  if (storagePaths.length > 0) {
    const { error: storageError } = await serviceClient.storage
      .from("listing-media")
      .remove(storagePaths);
    if (storageError) {
      console.warn("Deleted listing media cleanup must be retried", storageError);
    }
  }

  return json(result);
});
