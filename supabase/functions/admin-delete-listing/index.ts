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

  const { data: listing, error: listingError } = await serviceClient
    .from("listings")
    .select("id")
    .eq("id", listingId)
    .single();

  if (listingError || !listing) {
    return json({ error: "Listing not found" }, 404);
  }

  const { count: inquiryCount, error: inquiryError } = await serviceClient
    .from("booking_requests")
    .select("id", { count: "exact", head: true })
    .eq("listing_id", listingId);

  if (inquiryError) {
    return json({ error: inquiryError.message }, 500);
  }

  if ((inquiryCount ?? 0) > 0 && !confirmDeleteWithInquiries) {
    return json(
      {
        error: "Listings with inquiries require confirm_delete_with_inquiries = true",
        inquiryCount,
      },
      409,
    );
  }

  const { data: mediaRows, error: mediaError } = await serviceClient
    .from("listing_media")
    .select("storage_path, thumbnail_path")
    .eq("listing_id", listingId);

  if (mediaError) {
    return json({ error: mediaError.message }, 500);
  }

  const storagePaths = Array.from(
    new Set(
      (mediaRows ?? [])
        .flatMap((row) => [row.storage_path, row.thumbnail_path])
        .map(normalizeListingMediaPath)
        .filter((value): value is string => typeof value === "string" && value.length > 0),
    ),
  );

  if (storagePaths.length > 0) {
    const { error: storageError } = await serviceClient.storage
      .from("listing-media")
      .remove(storagePaths);
    if (storageError) {
      return json({ error: storageError.message }, 500);
    }
  }

  const { error: mediaDeleteError } = await serviceClient
    .from("listing_media")
    .delete()
    .eq("listing_id", listingId);

  if (mediaDeleteError) {
    return json({ error: mediaDeleteError.message }, 500);
  }

  const { error: deleteError } = await serviceClient
    .from("listings")
    .delete()
    .eq("id", listingId);

  if (deleteError) {
    return json({ error: deleteError.message }, 500);
  }

  await serviceClient.from("audit_logs").insert({
    actor_id: user.id,
    action: "admin_delete_listing",
    target_table: "listings",
    target_id: listingId,
    metadata: { listingId, inquiryCount, confirmDeleteWithInquiries },
  });

  return json({ success: true, listingId, listing_id: listingId });
});
