import { createClient } from "@supabase/supabase-js";

type QueryValue = string | number | boolean | null | undefined;

const supabaseUrl =
  process.env.SUPABASE_URL ?? "https://tlhoajedyaeaaqtrjqqh.supabase.co";
const supabasePublishableKey =
  process.env.SUPABASE_PUBLISHABLE_KEY ??
  "sb_publishable_3Txem_vMHZbvLswFzjR6ng_OGXbur1K";
let storageClient:
  | ReturnType<typeof createClient>
  | null = null;

function ensureEnv() {
  if (!supabaseUrl || !supabasePublishableKey) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_PUBLISHABLE_KEY");
  }
}

async function supabaseFetch(path: string, init?: RequestInit) {
  ensureEnv();
  const response = await fetch(`${supabaseUrl}${path}`, {
    ...init,
    headers: {
      apikey: supabasePublishableKey,
      Authorization: `Bearer ${supabasePublishableKey}`,
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
    cache: "no-store",
  });

  if (!response.ok) {
    throw new Error(await response.text());
  }

  return response.json();
}

function isMissingRpcSignature(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  return message.includes("PGRST202") || message.includes("schema cache");
}

function isPromotionRpcCompatibilityError(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  return (
    isMissingRpcSignature(error) ||
    message.includes("PGRST203") ||
    message.includes("Could not choose the best candidate function")
  );
}

function encodeParams(params: Record<string, QueryValue>) {
  const query = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== "") {
      query.set(key, String(value));
    }
  }
  return query.toString();
}

function getStorageClient() {
  ensureEnv();
  storageClient ??= createClient(supabaseUrl, supabasePublishableKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return storageClient;
}

async function createSignedListingMediaUrl(path?: string | null) {
  ensureEnv();
  if (!path) {
    return null;
  }
  const { data, error } = await getStorageClient().storage
    .from("listing-media")
    .createSignedUrl(path, 60);
  if (error) {
    return null;
  }
  return data.signedUrl;
}

async function createSignedPromotionMediaUrl(path?: string | null) {
  ensureEnv();
  if (!path) {
    return null;
  }
  const { data, error } = await getStorageClient().storage
    .from("platform-promotions")
    .createSignedUrl(path, 60);
  if (error) {
    return null;
  }
  return data.signedUrl;
}

export async function fetchCategories() {
  return supabaseFetch(
    `/rest/v1/asset_categories?select=id,name,slug,description,icon_key,display_order,home_feed_weight&is_active=eq.true&order=display_order.asc,name.asc`,
  );
}

export async function fetchPublicHomeFeed(params: {
  limit?: number;
  page?: number;
  regionId?: string;
  districtId?: string;
  wardId?: string;
  areaId?: string;
  latitude?: number;
  longitude?: number;
  sessionSeed?: string;
}) {
  let rows;
  try {
    rows = await supabaseFetch(`/rest/v1/rpc/get_public_home_feed`, {
      method: "POST",
      body: JSON.stringify({
        p_limit: params.limit ?? 20,
        p_page: params.page ?? 0,
        p_selected_region_id: params.regionId ?? null,
        p_selected_district_id: params.districtId ?? null,
        p_selected_ward_id: params.wardId ?? null,
        p_selected_area_id: params.areaId ?? null,
        p_latitude: params.latitude ?? null,
        p_longitude: params.longitude ?? null,
        p_session_seed: params.sessionSeed ?? null,
      }),
    });
  } catch (error) {
    if (!isMissingRpcSignature(error)) {
      throw error;
    }
    rows = await supabaseFetch(`/rest/v1/rpc/get_public_home_feed`, {
      method: "POST",
      body: JSON.stringify({
        p_limit: params.limit ?? 20,
        p_page: params.page ?? 0,
        p_selected_region_id: params.regionId ?? null,
        p_selected_district_id: params.districtId ?? null,
        p_latitude: params.latitude ?? null,
        p_longitude: params.longitude ?? null,
        p_session_seed: params.sessionSeed ?? null,
      }),
    });
  }
  return Promise.all(
    rows.map(async (row: Record<string, unknown>) => ({
      ...row,
      cover_url: await createSignedListingMediaUrl(
        row.cover_storage_path as string | null | undefined,
      ),
    })),
  );
}

export async function fetchPromotions(params: {
  surface: string;
  placement?: string;
  limit?: number;
}) {
  let rows;
  try {
    rows = await supabaseFetch(`/rest/v1/rpc/get_active_platform_promotions`, {
      method: "POST",
      body: JSON.stringify({
        p_surface: params.surface,
        p_placement: params.placement ?? "global",
        p_limit: params.limit ?? 3,
      }),
    });
  } catch (error) {
    if (!isPromotionRpcCompatibilityError(error)) {
      throw error;
    }
    rows = await supabaseFetch(`/rest/v1/rpc/get_active_platform_promotions`, {
      method: "POST",
      body: JSON.stringify({
        p_placement: params.placement ?? "global",
        p_limit: params.limit ?? 3,
      }),
    });
  }
  return Promise.all(
    rows.map(async (row: Record<string, unknown>) => ({
      ...row,
      media_url: await createSignedPromotionMediaUrl(
        row.media_path as string | null | undefined,
      ),
      thumbnail_url: await createSignedPromotionMediaUrl(
        row.thumbnail_path as string | null | undefined,
      ),
    })),
  );
}

export async function fetchPublicListings(params: {
  categorySlug?: string;
  searchText?: string;
  regionId?: string;
  districtId?: string;
  wardId?: string;
  areaId?: string;
  limit?: number;
  page?: number;
  latitude?: number;
  longitude?: number;
  sessionSeed?: string;
}) {
  let rows;
  try {
    rows = await supabaseFetch(`/rest/v1/rpc/get_public_listings`, {
      method: "POST",
      body: JSON.stringify({
        p_category_slug: params.categorySlug ?? null,
        p_search_text: params.searchText ?? null,
        p_region_id: params.regionId ?? null,
        p_district_id: params.districtId ?? null,
        p_ward_id: params.wardId ?? null,
        p_area_id: params.areaId ?? null,
        p_limit: params.limit ?? 20,
        p_page: params.page ?? 0,
        p_latitude: params.latitude ?? null,
        p_longitude: params.longitude ?? null,
        p_session_seed: params.sessionSeed ?? null,
      }),
    });
  } catch (error) {
    if (!isMissingRpcSignature(error)) {
      throw error;
    }
    rows = await supabaseFetch(`/rest/v1/rpc/get_public_listings`, {
      method: "POST",
      body: JSON.stringify({
        p_category_slug: params.categorySlug ?? null,
        p_search_text: params.searchText ?? null,
        p_region_id: params.regionId ?? null,
        p_district_id: params.districtId ?? null,
        p_limit: params.limit ?? 20,
        p_page: params.page ?? 0,
        p_latitude: params.latitude ?? null,
        p_longitude: params.longitude ?? null,
        p_session_seed: params.sessionSeed ?? null,
      }),
    });
  }
  return Promise.all(
    rows.map(async (row: Record<string, unknown>) => ({
      ...row,
      cover_url: await createSignedListingMediaUrl(
        row.cover_storage_path as string | null | undefined,
      ),
    })),
  );
}

export async function fetchListingDetail(listingId: string) {
  const rows = await supabaseFetch(`/rest/v1/rpc/get_public_listing_detail`, {
    method: "POST",
    body: JSON.stringify({ p_listing_id: listingId }),
  });
  const row = rows[0];
  if (!row) {
    return null;
  }
  const media = await Promise.all(
    ((row.media ?? []) as Array<Record<string, unknown>>).map(async (item) => ({
      ...item,
      signed_url: await createSignedListingMediaUrl(
        item.storage_path as string | null | undefined,
      ),
    })),
  );
  return {
    id: row.listing_id,
    title: row.title,
    description: row.description,
    public_location_label: row.public_location_label,
    price_amount: row.price_amount,
    price_period: row.price_period,
    listing_rules: row.listing_rules,
    listing_attributes: row.listing_attributes ?? {},
    asset_categories: {
      name: row.category_name,
      slug: row.category_slug,
      field_schema: row.category_field_schema ?? [],
    },
    listing_media: media,
  };
}

export async function fetchCountryId() {
  const rows = await supabaseFetch(
    `/rest/v1/locations?select=id,name&location_type=eq.country&is_active=eq.true&order=name.asc&limit=1`,
  );
  return rows[0]?.id as string | undefined;
}

export async function fetchLocations(params: {
  locationType: string;
  parentId?: string;
}) {
  const query = encodeParams({
    select: "id,name,location_type,parent_id",
    location_type: `eq.${params.locationType}`,
    is_active: "eq.true",
    parent_id: params.parentId ? `eq.${params.parentId}` : "is.null",
    order: "name.asc",
  });
  return supabaseFetch(`/rest/v1/locations?${query}`);
}

export async function submitGuestRequest(body: {
  listing_id: string;
  customer_name: string;
  customer_phone_number: string;
}) {
  ensureEnv();
  const response = await fetch(
    `${supabaseUrl}/functions/v1/create-guest-booking-request`,
    {
      method: "POST",
      headers: {
        apikey: supabasePublishableKey,
        Authorization: `Bearer ${supabasePublishableKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    },
  );

  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload.error ?? "Request failed");
  }
  return payload;
}
