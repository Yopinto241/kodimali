import { cache } from "react";
import { supabaseFetch, createSignedListingMediaUrl } from "@/lib/supabase-public";
import { isPublicId } from "@/lib/seo";

export type PublicEventRow = Record<string, unknown>;
export type EventKind = "equipment" | "service";
// Keep this whitelist aligned with the existing anonymous detail UI. Never use a service-role client.
const equipmentFields = "id,name,description,specifications,public_location_label,total_quantity,price_amount_tzs,price_unit,setup_minutes,return_buffer_minutes,transport_configuration,cleaning_configuration,return_procedure,security_deposit_tzs,damage_rules,cancellation_policy,media_paths,event_equipment_categories(name_sw,name_en)";
const serviceFields = "id,title,description,pricing_mode,price_amount_tzs,duration_minutes,requirements,travel_configuration,included_equipment,cancellation_policy,event_service_profiles!inner(id,display_name,provider_kind,biography,experience_years,service_requirements,portfolio_media,event_service_areas(locations(name,location_type)))";

export const fetchPublicEventDetail = cache(async (kind: EventKind, id: string) => {
  if (!isPublicId(id)) return null;
  const query = new URLSearchParams({ select: kind === "equipment" ? equipmentFields : serviceFields, id: `eq.${id}`, is_active: "eq.true", publication_status: "eq.published", limit: "1" });
  if (kind === "equipment") query.set("verification_status", "eq.verified");
  else { query.set("event_service_profiles.verification_status", "eq.verified"); query.set("event_service_profiles.is_active", "eq.true"); }
  const rows = await supabaseFetch(`/rest/v1/${kind === "equipment" ? "event_equipment_items" : "event_service_offerings"}?${query}`, undefined, { revalidate: 60, tags: ["public-events"] }) as PublicEventRow[];
  const row = rows[0];
  if (!row) return null;
  const profile = row.event_service_profiles as PublicEventRow | null;
  const media = kind === "equipment" ? row.media_paths : profile?.portfolio_media;
  const paths = Array.isArray(media) ? media.filter((path): path is string => typeof path === "string").slice(0, 8) : [];
  const images = (await Promise.all(paths.map(path => /^https?:\/\//.test(path) ? path : createSignedListingMediaUrl(path)))).filter((url): url is string => Boolean(url));
  return { row, images };
});

export async function fetchEventCatalog(kind: EventKind) {
  return supabaseFetch(`/rest/v1/rpc/search_public_event_${kind === "equipment" ? "equipment" : "services"}`, { method: "POST", body: JSON.stringify({ p_limit: 31, p_offset: 0 }) }, { revalidate: 60, tags: ["public-events"] }) as Promise<PublicEventRow[]>;
}

export async function fetchEventCategories() {
  return supabaseFetch("/rest/v1/event_equipment_categories?select=id,name_sw,name_en&is_active=eq.true&order=display_order", undefined, { revalidate: 3600 }) as Promise<PublicEventRow[]>;
}
