"use client";
import { useNavigate } from "@/components/navigation-progress";
import { browserPreferences } from "@/lib/browser-preferences";
import { UiText } from "@/components/ui-text";

export function ClearListingFilters({ path }: { path: string }) {
  const navigate = useNavigate();
  return <button type="button" className="search-clear-filters text-sm font-semibold text-white underline" onClick={(event) => {
    for (const key of ["region_id", "district_id", "ward_id", "area_id", "latitude", "longitude"]) browserPreferences.removeItem(`customer_${key}`);
    const form = event.currentTarget.form;
    form?.reset();
    form?.querySelectorAll("details").forEach((panel) => { panel.open = false; });
    form?.dispatchEvent(new CustomEvent("kodimali-filter-error", { detail: "" }));
    navigate(path);
  }}><UiText text="Clear filters" /></button>;
}
