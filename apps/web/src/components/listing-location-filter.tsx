"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";

import { useLanguage } from "@/components/language-provider";

type LocationOption = { id: string; name: string };

export function ListingLocationFilter({
  regions,
  initialRegionId = "",
  initialDistrictId = "",
  initialRegionName = "",
  initialDistrictName = "",
}: {
  regions: LocationOption[];
  initialRegionId?: string;
  initialDistrictId?: string;
  initialRegionName?: string;
  initialDistrictName?: string;
}) {
  const router = useRouter();
  const { language } = useLanguage();
  const sw = language === "sw";
  const rootRef = useRef<HTMLDivElement>(null);
  const [open, setOpen] = useState(false);
  const [pending, startTransition] = useTransition();
  const [regionId, setRegionId] = useState(initialRegionId);
  const [districtId, setDistrictId] = useState(initialDistrictId);
  const [districts, setDistricts] = useState<LocationOption[]>([]);
  const [loadingDistricts, setLoadingDistricts] = useState(false);

  const selectedRegion = regions.find((item) => item.id === initialRegionId)?.name || initialRegionName;
  const selectedLabel = initialDistrictName || selectedRegion || (sw ? "Eneo lote" : "Any location");

  useEffect(() => {
    function close(event: PointerEvent) {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    }
    function escape(event: KeyboardEvent) {
      if (event.key === "Escape") setOpen(false);
    }
    document.addEventListener("pointerdown", close);
    document.addEventListener("keydown", escape);
    return () => {
      document.removeEventListener("pointerdown", close);
      document.removeEventListener("keydown", escape);
    };
  }, []);

  useEffect(() => {
    if (!initialRegionId) return;
    void loadDistricts(initialRegionId);
  }, [initialRegionId]);

  async function loadDistricts(nextRegionId: string) {
    if (!nextRegionId) {
      setDistricts([]);
      return;
    }
    setLoadingDistricts(true);
    try {
      const response = await fetch(`/api/locations?locationType=district&parentId=${encodeURIComponent(nextRegionId)}`);
      setDistricts(response.ok ? await response.json() : []);
    } finally {
      setLoadingDistricts(false);
    }
  }

  function navigate(nextRegionId: string, nextDistrictId: string) {
    const url = new URL(window.location.href);
    url.searchParams.delete("page");
    url.searchParams.delete("wardId");
    url.searchParams.delete("areaId");
    url.searchParams.delete("lat");
    url.searchParams.delete("lng");
    if (nextRegionId) url.searchParams.set("regionId", nextRegionId);
    else url.searchParams.delete("regionId");
    if (nextDistrictId) url.searchParams.set("districtId", nextDistrictId);
    else url.searchParams.delete("districtId");

    if (nextRegionId) window.localStorage.setItem("customer_region_id", nextRegionId);
    else window.localStorage.removeItem("customer_region_id");
    if (nextDistrictId) window.localStorage.setItem("customer_district_id", nextDistrictId);
    else window.localStorage.removeItem("customer_district_id");
    window.localStorage.removeItem("customer_ward_id");
    window.localStorage.removeItem("customer_area_id");

    setOpen(false);
    startTransition(() => router.push(`${url.pathname}${url.search}`));
  }

  return (
    <div className="listing-location-filter" ref={rootRef}>
      <button
        type="button"
        className="listing-location-trigger"
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
      >
        <span aria-hidden="true">⌖</span>
        <span>{selectedLabel}</span>
        <span aria-hidden="true">⌄</span>
      </button>
      {open ? (
        <div className="listing-location-menu">
          <div className="listing-location-menu-head">
            <strong>{sw ? "Chagua eneo" : "Choose location"}</strong>
            {(initialRegionId || initialDistrictId) ? (
              <button type="button" onClick={() => navigate("", "")}>{sw ? "Ondoa" : "Clear"}</button>
            ) : null}
          </div>
          <label>
            <span>{sw ? "Mkoa" : "Region"}</span>
            <select
              value={regionId}
              onChange={(event) => {
                const next = event.target.value;
                setRegionId(next);
                setDistrictId("");
                void loadDistricts(next);
              }}
            >
              <option value="">{sw ? "Mikoa yote" : "All regions"}</option>
              {regions.map((region) => <option key={region.id} value={region.id}>{region.name}</option>)}
            </select>
          </label>
          {regionId ? (
            <label>
              <span>{sw ? "Wilaya (si lazima)" : "District (optional)"}</span>
              <select value={districtId} onChange={(event) => setDistrictId(event.target.value)} disabled={loadingDistricts}>
                <option value="">{loadingDistricts ? (sw ? "Inapakia..." : "Loading...") : (sw ? "Wilaya zote" : "All districts")}</option>
                {districts.map((district) => <option key={district.id} value={district.id}>{district.name}</option>)}
              </select>
            </label>
          ) : null}
          <button type="button" className="listing-location-apply" disabled={pending} onClick={() => navigate(regionId, districtId)}>
            {pending ? (sw ? "Inafungua..." : "Loading...") : (sw ? "Onyesha" : "Show results")}
          </button>
        </div>
      ) : null}
    </div>
  );
}
