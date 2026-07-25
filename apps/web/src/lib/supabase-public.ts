import { unstable_cache } from "next/cache";
import { createClient } from "@supabase/supabase-js";

type QueryValue = string | number | boolean | null | undefined;
export type PublicCategory = {
  id: string;
  name: string;
  slug: string;
  description?: string | null;
  icon_key?: string | null;
  display_order?: number | null;
  home_feed_weight?: number | null;
};

const supabaseUrl =
  process.env.SUPABASE_URL ?? "https://tlhoajedyaeaaqtrjqqh.supabase.co";
const supabasePublishableKey =
  process.env.SUPABASE_PUBLISHABLE_KEY ??
  "sb_publishable_3Txem_vMHZbvLswFzjR6ng_OGXbur1K";
const signedMediaUrlSeconds = 60 * 60;
const cacheTtl = {
  categories: 60 * 60,
  locations: 60 * 60,
  promotions: 5 * 60,
  homeFeed: 2 * 60,
  listings: 2 * 60,
  listingDetail: 15,
} as const;

let storageClient:
  | ReturnType<typeof createClient>
  | null = null;

function ensureEnv() {
  if (!supabaseUrl || !supabasePublishableKey) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_PUBLISHABLE_KEY");
  }
}

async function supabaseFetch(
  path: string,
  init?: RequestInit,
  options?: {
    revalidate?: number;
    tags?: string[];
  },
) {
  ensureEnv();
  const response = await fetch(`${supabaseUrl}${path}`, {
    ...init,
    headers: {
      apikey: supabasePublishableKey,
      Authorization: `Bearer ${supabasePublishableKey}`,
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
    next:
      options?.revalidate != null || options?.tags?.length
        ? {
            revalidate: options?.revalidate,
            tags: options?.tags,
          }
        : undefined,
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

function serializeCacheInput(params: Record<string, QueryValue>) {
  return JSON.stringify(
    Object.entries(params)
      .filter(([, value]) => value !== undefined && value !== null && value !== "")
      .sort(([left], [right]) => left.localeCompare(right)),
  );
}

function cacheQuery<T>(
  namespace: string,
  key: string,
  revalidate: number,
  tags: string[],
  loader: () => Promise<T>,
) {
  return unstable_cache(loader, [namespace, key], {
    revalidate,
    tags,
  })();
}

function getStorageClient() {
  ensureEnv();
  storageClient ??= createClient(supabaseUrl, supabasePublishableKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return storageClient;
}

export async function checkPublicBackendHealth() {
  const paymentRequired = await supabaseFetch(
    "/rest/v1/rpc/contact_payments_enabled",
    { method: "POST", body: "{}", cache: "no-store" },
  );
  return { supabase: "ok", contactPaymentsEnabled: paymentRequired !== false };
}

const createSignedListingMediaUrl = unstable_cache(
  async (path?: string | null) => {
    ensureEnv();
    if (!path) {
      return null;
    }
    const { data, error } = await getStorageClient().storage
      .from("listing-media")
      .createSignedUrl(path, signedMediaUrlSeconds);
    if (error) {
      return null;
    }
    return data.signedUrl;
  },
  ["listing-media-signed-url"],
  {
    revalidate: cacheTtl.listings,
    tags: ["public-listing-media"],
  },
);

const createSignedPromotionMediaUrl = unstable_cache(
  async (path?: string | null) => {
    ensureEnv();
    if (!path) {
      return null;
    }
    const { data, error } = await getStorageClient().storage
      .from("platform-promotions")
      .createSignedUrl(path, signedMediaUrlSeconds);
    if (error) {
      return null;
    }
    return data.signedUrl;
  },
  ["promotion-media-signed-url"],
  {
    revalidate: cacheTtl.promotions,
    tags: ["public-promotions"],
  },
);

function withApartmentFallback(categories: PublicCategory[]) {
  const normalized = categories.map((category) => ({ ...category }));
  if (normalized.some((category) => category.slug === "apartment")) {
    return normalized;
  }
  return [
    {
      id: "apartment-fallback",
      name: "Apartment",
      slug: "apartment",
      description:
        "Serviced apartments, flats, and short-stay homes for local and international guests.",
      icon_key: "apartment",
      display_order: 2,
      home_feed_weight: 9,
    },
    ...normalized,
  ];
}

export async function fetchCategories(): Promise<PublicCategory[]> {
  return cacheQuery(
    "public-categories",
    "all",
    cacheTtl.categories,
    ["public-categories"],
    async () =>
      withApartmentFallback(
        (await supabaseFetch(
          `/rest/v1/asset_categories?select=id,name,slug,description,icon_key,display_order,home_feed_weight&is_active=eq.true&order=display_order.asc,name.asc`,
          undefined,
          {
            revalidate: cacheTtl.categories,
            tags: ["public-categories"],
          },
        )) as PublicCategory[],
      ),
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
  const normalizedParams = {
    limit: params.limit ?? 20,
    page: params.page ?? 0,
    regionId: params.regionId ?? null,
    districtId: params.districtId ?? null,
    wardId: params.wardId ?? null,
    areaId: params.areaId ?? null,
    latitude: params.latitude ?? null,
    longitude: params.longitude ?? null,
    sessionSeed: params.sessionSeed ?? null,
  };

  return cacheQuery(
    "public-home-feed",
    serializeCacheInput(normalizedParams),
    cacheTtl.homeFeed,
    ["public-home-feed", "public-listings"],
    async () => {
      let rows;
      try {
        rows = await supabaseFetch(
          `/rest/v1/rpc/get_public_home_feed`,
          {
            method: "POST",
            body: JSON.stringify({
              p_limit: normalizedParams.limit,
              p_page: normalizedParams.page,
              p_selected_region_id: normalizedParams.regionId,
              p_selected_district_id: normalizedParams.districtId,
              p_selected_ward_id: normalizedParams.wardId,
              p_selected_area_id: normalizedParams.areaId,
              p_latitude: normalizedParams.latitude,
              p_longitude: normalizedParams.longitude,
              p_session_seed: normalizedParams.sessionSeed,
            }),
          },
          {
            revalidate: cacheTtl.homeFeed,
            tags: ["public-home-feed", "public-listings"],
          },
        );
      } catch (error) {
        if (!isMissingRpcSignature(error)) {
          throw error;
        }
        rows = await supabaseFetch(
          `/rest/v1/rpc/get_public_home_feed`,
          {
            method: "POST",
            body: JSON.stringify({
              p_limit: normalizedParams.limit,
              p_page: normalizedParams.page,
              p_selected_region_id: normalizedParams.regionId,
              p_selected_district_id: normalizedParams.districtId,
              p_latitude: normalizedParams.latitude,
              p_longitude: normalizedParams.longitude,
              p_session_seed: normalizedParams.sessionSeed,
            }),
          },
          {
            revalidate: cacheTtl.homeFeed,
            tags: ["public-home-feed", "public-listings"],
          },
        );
      }

      return Promise.all(
        rows.map(async (row: Record<string, unknown>) => ({
          ...row,
          cover_url: await createSignedListingMediaUrl(
            row.cover_storage_path as string | null | undefined,
          ),
        })),
      );
    },
  );
}

export async function fetchPromotions(params: {
  surface: string;
  placement?: string;
  limit?: number;
}) {
  const normalizedParams = {
    surface: params.surface,
    placement: params.placement ?? "global",
    limit: params.limit ?? 3,
  };

  return cacheQuery(
    "public-promotions",
    serializeCacheInput(normalizedParams),
    cacheTtl.promotions,
    ["public-promotions"],
    async () => {
      let rows;
      try {
        rows = await supabaseFetch(
          `/rest/v1/rpc/get_active_platform_promotions`,
          {
            method: "POST",
            body: JSON.stringify({
              p_surface: normalizedParams.surface,
              p_placement: normalizedParams.placement,
              p_limit: normalizedParams.limit,
            }),
          },
          {
            revalidate: cacheTtl.promotions,
            tags: ["public-promotions"],
          },
        );
      } catch (error) {
        if (!isPromotionRpcCompatibilityError(error)) {
          throw error;
        }
        rows = await supabaseFetch(
          `/rest/v1/rpc/get_active_platform_promotions`,
          {
            method: "POST",
            body: JSON.stringify({
              p_placement: normalizedParams.placement,
              p_limit: normalizedParams.limit,
            }),
          },
          {
            revalidate: cacheTtl.promotions,
            tags: ["public-promotions"],
          },
        );
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
    },
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
  const normalizedParams = {
    categorySlug: params.categorySlug ?? null,
    searchText: params.searchText ?? null,
    regionId: params.regionId ?? null,
    districtId: params.districtId ?? null,
    wardId: params.wardId ?? null,
    areaId: params.areaId ?? null,
    limit: params.limit ?? 20,
    page: params.page ?? 0,
    latitude: params.latitude ?? null,
    longitude: params.longitude ?? null,
    sessionSeed: params.sessionSeed ?? null,
  };

  return cacheQuery(
    "public-listings",
    serializeCacheInput(normalizedParams),
    cacheTtl.listings,
    ["public-listings"],
    async () => {
      let rows;
      try {
        rows = await supabaseFetch(
          `/rest/v1/rpc/get_public_listings`,
          {
            method: "POST",
            body: JSON.stringify({
              p_category_slug: normalizedParams.categorySlug,
              p_search_text: normalizedParams.searchText,
              p_region_id: normalizedParams.regionId,
              p_district_id: normalizedParams.districtId,
              p_ward_id: normalizedParams.wardId,
              p_area_id: normalizedParams.areaId,
              p_limit: normalizedParams.limit,
              p_page: normalizedParams.page,
              p_latitude: normalizedParams.latitude,
              p_longitude: normalizedParams.longitude,
              p_session_seed: normalizedParams.sessionSeed,
            }),
          },
          {
            revalidate: cacheTtl.listings,
            tags: ["public-listings"],
          },
        );
      } catch (error) {
        if (!isMissingRpcSignature(error)) {
          throw error;
        }
        rows = await supabaseFetch(
          `/rest/v1/rpc/get_public_listings`,
          {
            method: "POST",
            body: JSON.stringify({
              p_category_slug: normalizedParams.categorySlug,
              p_search_text: normalizedParams.searchText,
              p_region_id: normalizedParams.regionId,
              p_district_id: normalizedParams.districtId,
              p_limit: normalizedParams.limit,
              p_page: normalizedParams.page,
              p_latitude: normalizedParams.latitude,
              p_longitude: normalizedParams.longitude,
              p_session_seed: normalizedParams.sessionSeed,
            }),
          },
          {
            revalidate: cacheTtl.listings,
            tags: ["public-listings"],
          },
        );
      }

      return Promise.all(
        rows.map(async (row: Record<string, unknown>) => ({
          ...row,
          cover_url: await createSignedListingMediaUrl(
            row.cover_storage_path as string | null | undefined,
          ),
        })),
      );
    },
  );
}

export async function fetchListingDetail(listingId: string) {
  return cacheQuery(
    "public-listing-detail",
    listingId,
    cacheTtl.listingDetail,
    [`public-listing-${listingId}`, "public-listings"],
    async () => {
      const rows = await supabaseFetch(
        `/rest/v1/rpc/get_public_listing_detail`,
        {
          method: "POST",
          body: JSON.stringify({ p_listing_id: listingId }),
        },
        {
          revalidate: cacheTtl.listingDetail,
          tags: [`public-listing-${listingId}`, "public-listings"],
        },
      );
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
        region_id: row.region_id,
        district_id: row.district_id,
        ward_id: row.ward_id,
        area_id: row.area_id,
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
        agent_summary: {
          id: row.agent_id,
          display_name: row.agent_display_name,
          business_name: row.agent_business_name,
          phone_number: row.agent_phone_number,
          location_label: row.agent_location_label,
          verification_status: row.agent_verification_status,
          verified_at: row.agent_verified_at,
          profile_photo_url: row.agent_profile_photo_path ?? null,
        },
        listing_media: media,
      };
    },
  );
}

export async function fetchCountryId() {
  return cacheQuery(
    "public-country-id",
    "tanzania",
    cacheTtl.locations,
    ["public-locations"],
    async () => {
      const rows = await supabaseFetch(
        `/rest/v1/locations?select=id,name&location_type=eq.country&is_active=eq.true&order=name.asc&limit=1`,
        undefined,
        {
          revalidate: cacheTtl.locations,
          tags: ["public-locations"],
        },
      );
      return rows[0]?.id as string | undefined;
    },
  );
}

export async function fetchLocations(params: {
  locationType: string;
  parentId?: string;
}) {
  const normalizedParams = {
    locationType: params.locationType,
    parentId: params.parentId ?? null,
  };
  return cacheQuery(
    "public-locations",
    serializeCacheInput(normalizedParams),
    cacheTtl.locations,
    ["public-locations"],
    async () => {
      const query = encodeParams({
        select: "id,name,location_type,parent_id",
        location_type: `eq.${params.locationType}`,
        is_active: "eq.true",
        parent_id: params.parentId ? `eq.${params.parentId}` : "is.null",
        order: "name.asc",
      });
      return supabaseFetch(`/rest/v1/locations?${query}`, undefined, {
        revalidate: cacheTtl.locations,
        tags: ["public-locations"],
      });
    },
  );
}

export async function submitGuestRequest(body: {
  listing_id: string;
  customer_name: string;
  customer_email?: string;
  customer_phone_number?: string;
  requested_start_at?: string;
  requested_end_at?: string;
  guest_count?: number;
  request_message?: string;
  requested_service_codes?: string[];
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
    const message =
      typeof payload?.error === "string" ? payload.error : "Request failed";
    if (
      message.toLowerCase().includes("listing not found") ||
      message.toLowerCase().includes("listing is not available") ||
      message.toLowerCase().includes("not accepting public requests")
    ) {
      throw new Error(
        "This listing is no longer available. Refresh the listings and choose another one.",
      );
    }
    throw new Error(message);
  }
  return payload;
}

export async function checkListingAvailability(body: {
  listingId: string;
  requestedStartAt?: string;
  requestedEndAt?: string;
}) {
  ensureEnv();
  const response = await fetch(`${supabaseUrl}/functions/v1/check-availability`, {
    method: "POST",
    headers: {
      apikey: supabasePublishableKey,
      Authorization: `Bearer ${supabasePublishableKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload.error ?? "Availability check failed");
  }
  return payload;
}
