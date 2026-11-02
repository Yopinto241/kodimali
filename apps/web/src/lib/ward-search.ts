export type WardLocation = { region_id: string; district_id: string; ward_id: string; ward_name?: string | null };
export function wardLocation(value: unknown): WardLocation | null {
  if (!value || typeof value !== "object") return null;
  const row = value as Record<string, unknown>;
  return ["region_id", "district_id", "ward_id"].every((key) => typeof row[key] === "string" && row[key]) ? row as WardLocation : null;
}
export function applyWardLocation(url: URL, location: WardLocation) {
  for (const key of ["lat", "lng", "areaId", "page"]) url.searchParams.delete(key);
  url.searchParams.set("regionId", location.region_id);
  url.searchParams.set("districtId", location.district_id);
  url.searchParams.set("wardId", location.ward_id);
  return url;
}
