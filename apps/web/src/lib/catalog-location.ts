import { optionalNumber } from "@/lib/listing-search";
import { supabaseFetch } from "@/lib/supabase-public";
import { wardLocation } from "@/lib/ward-search";

/** Legacy GPS links also search the whole ward; coordinates never reach search. */
export async function catalogLocation(params: Record<string, string | string[] | undefined>) {
  const value = (key: string) => typeof params[key] === "string" ? params[key] as string : undefined;
  const manual = { regionId: value("regionId"), districtId: value("districtId"), wardId: value("wardId"), areaId: value("areaId") };
  const latitude = optionalNumber(params.lat), longitude = optionalNumber(params.lng);
  if (latitude === undefined || longitude === undefined) return manual;
  if (manual.wardId) return { ...manual, areaId: undefined };
  try {
    const rows = await supabaseFetch("/rest/v1/rpc/resolve_location_hierarchy", { method: "POST", signal: AbortSignal.timeout(10000), body: JSON.stringify({ p_latitude: latitude, p_longitude: longitude }) });
    const ward = wardLocation(rows?.[0]);
    if (ward) return { regionId: ward.region_id, districtId: ward.district_id, wardId: ward.ward_id, areaId: undefined };
  } catch { /* Manual selection stays available when old GPS links cannot resolve. */ }
  return { ...manual, areaId: undefined };
}
