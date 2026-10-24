"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState, useTransition } from "react";

import { StatusPill } from "@/components/status-pill";
import { useLanguage } from "@/components/language-provider";
import { getBrowserSupabase } from "@/lib/supabase-browser";

type LocationOption = { id: string; name: string };

export function LocationBanner({
  visibleByDefault,
  regions,
  persistent = false,
}: {
  visibleByDefault: boolean;
  regions: LocationOption[];
  persistent?: boolean;
}) {
  const router = useRouter();
  const { language } = useLanguage();
  const sw = language === "sw";
  const [isNavigating, startTransition] = useTransition();
  // The initial client render must exactly match the server output. Browser-only
  // preferences are applied after hydration so localStorage cannot change the
  // shape of the hydrated tree.
  const [visible, setVisible] = useState(visibleByDefault);
  const [manualOpen, setManualOpen] = useState(false);
  const [regionId, setRegionId] = useState("");
  const [districtId, setDistrictId] = useState("");
  const [wardId, setWardId] = useState("");
  const [areaId, setAreaId] = useState("");
  const [districts, setDistricts] = useState<LocationOption[]>([]);
  const [wards, setWards] = useState<LocationOption[]>([]);
  const [areas, setAreas] = useState<LocationOption[]>([]);
  const [locationMessage, setLocationMessage] = useState("");
  const [isLocating, setIsLocating] = useState(false);

  useEffect(() => {
    if (persistent) return;
    const timer = window.setTimeout(() => {
      const hiddenUntil = window.localStorage.getItem(
        "customer_location_banner_hidden_until",
      );
      if (hiddenUntil && Number(hiddenUntil) > Date.now()) {
        setVisible(false);
      }
    }, 0);
    return () => window.clearTimeout(timer);
  }, [persistent]);

  function buildBaseUrl() {
    return new URL(window.location.href);
  }

  function navigateTo(baseUrl: URL) {
    const target = `${baseUrl.pathname}${baseUrl.search}${baseUrl.hash}`;
    startTransition(() => {
      router.push(target);
    });
  }

  async function useGps() {
    if (!navigator.geolocation) {
      setLocationMessage(sw ? "Kifaa hiki hakiwezi kutambua eneo." : "This device cannot detect its location.");
      return;
    }
    setIsLocating(true);
    setLocationMessage(sw ? "Tunatafuta eneo ulipo..." : "Finding your location...");
    navigator.geolocation.getCurrentPosition(async (position) => {
      const latitude = position.coords.latitude;
      const longitude = position.coords.longitude;
      const { data, error } = await getBrowserSupabase().rpc("resolve_location_hierarchy", {
        p_latitude: latitude,
        p_longitude: longitude,
      } as never);
      const resolved = Array.isArray(data) ? data[0] as Record<string, string | null> : null;
      if (error || !resolved?.region_id) {
        setIsLocating(false);
        setLocationMessage(sw ? "Hatukuweza kuoanisha GPS na eneo. Chagua eneo mwenyewe." : "We could not match GPS to an area. Please choose it manually.");
        return;
      }
      const baseUrl = buildBaseUrl();
      window.localStorage.setItem(
        "customer_location_banner_hidden_until",
        String(Date.now() + 3 * 24 * 60 * 60 * 1000),
      );
      for (const [key, value] of [["region", resolved.region_id], ["district", resolved.district_id], ["ward", resolved.ward_id], ["area", resolved.area_id]]) {
        const storageKey = `customer_${key}_id`;
        const queryKey = `${key}Id`;
        if (value) { window.localStorage.setItem(storageKey, value); baseUrl.searchParams.set(queryKey, value); }
        else { window.localStorage.removeItem(storageKey); baseUrl.searchParams.delete(queryKey); }
      }
      window.localStorage.setItem("customer_latitude", String(latitude));
      window.localStorage.setItem("customer_longitude", String(longitude));
      baseUrl.searchParams.set("lat", String(latitude));
      baseUrl.searchParams.set("lng", String(longitude));
      setIsLocating(false);
      setLocationMessage("");
      navigateTo(baseUrl);
    }, () => {
      setIsLocating(false);
      setLocationMessage(sw ? "Ruhusu GPS, au chagua eneo mwenyewe." : "Allow location access, or choose an area manually.");
    }, { enableHighAccuracy: true, timeout: 15000, maximumAge: 60000 });
  }

  async function loadDistricts(nextRegionId: string) {
    if (!nextRegionId) {
      setDistricts([]);
      return;
    }

    const response = await fetch(
      `/api/locations?locationType=district&parentId=${nextRegionId}`,
    );
    const payload = await response.json();
    setDistricts(payload);
  }

  async function loadWards(nextDistrictId: string) {
    if (!nextDistrictId) {
      setWards([]);
      setAreas([]);
      return;
    }

    const [wardResponse, areaResponse] = await Promise.all([
      fetch(`/api/locations?locationType=ward&parentId=${nextDistrictId}`),
      fetch(`/api/locations?locationType=area&parentId=${nextDistrictId}`),
    ]);
    const [wardPayload, areaPayload] = await Promise.all([
      wardResponse.json(),
      areaResponse.json(),
    ]);
    setWards(wardPayload);
    setAreas(areaPayload);
  }

  async function loadAreas(nextParentId: string) {
    if (!nextParentId) {
      setAreas([]);
      return;
    }

    const response = await fetch(
      `/api/locations?locationType=area&parentId=${nextParentId}`,
    );
    const payload = await response.json();
    setAreas(payload);
  }

  function skipBanner() {
    window.localStorage.setItem(
      "customer_location_banner_hidden_until",
      String(Date.now() + 3 * 24 * 60 * 60 * 1000),
    );
    setVisible(false);
  }

  function applyManualLocation() {
    const baseUrl = buildBaseUrl();
    window.localStorage.setItem(
      "customer_location_banner_hidden_until",
      String(Date.now() + 3 * 24 * 60 * 60 * 1000),
    );
    window.localStorage.setItem("customer_region_id", regionId);
    window.localStorage.setItem("customer_district_id", districtId);
    if (wardId) {
      window.localStorage.setItem("customer_ward_id", wardId);
    } else {
      window.localStorage.removeItem("customer_ward_id");
    }
    if (areaId) {
      window.localStorage.setItem("customer_area_id", areaId);
    } else {
      window.localStorage.removeItem("customer_area_id");
    }
    window.localStorage.removeItem("customer_latitude");
    window.localStorage.removeItem("customer_longitude");
    baseUrl.searchParams.set("regionId", regionId);
    baseUrl.searchParams.set("districtId", districtId);
    if (wardId) {
      baseUrl.searchParams.set("wardId", wardId);
    } else {
      baseUrl.searchParams.delete("wardId");
    }
    if (areaId) {
      baseUrl.searchParams.set("areaId", areaId);
    } else {
      baseUrl.searchParams.delete("areaId");
    }
    baseUrl.searchParams.delete("lat");
    baseUrl.searchParams.delete("lng");
    navigateTo(baseUrl);
  }

  if (!visible && !persistent) {
    return null;
  }

  return (
    <section className="surface-card rounded-[20px] p-5 sm:p-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="max-w-2xl">
          <div className="flex flex-wrap items-center gap-3">
            <p className="eyebrow">{sw ? "Chagua eneo" : "Location setup"}</p>
            <StatusPill label={sw ? "Eneo lako ni la faragha" : "Your precise location stays private"} tone="info" />
          </div>
          <h2 className="mt-3 font-heading text-2xl font-semibold text-brand-ink sm:text-3xl">
            {sw ? "Unatafuta mali karibu na ulipo?" : "Looking for something near you?"}
          </h2>
          <p className="section-copy mt-3 text-base">
            {sw ? "Chagua eneo lako ili tukuonyeshe mali zinazopatikana karibu nawe. Tunaonyesha eneo la jumla tu; anwani kamili ya mali hubaki siri." : "Choose your area to see relevant properties nearby. KODIMALI shows only the general area; the property's exact address remains private."}
          </p>
        </div>
      </div>
      <div className="mt-5 flex flex-wrap gap-3">
        <button
          type="button"
          onClick={useGps}
          disabled={isNavigating || isLocating}
          className="btn btn-primary"
        >
          {isLocating ? (sw ? "Inatafuta..." : "Locating...") : (sw ? "Tumia eneo nilipo" : "Use my location")}
        </button>
        <button
          type="button"
          onClick={() => setManualOpen((value) => !value)}
          disabled={isNavigating}
          className="btn btn-outline"
        >
          {sw ? "Chagua eneo" : "Choose an area"}
        </button>
        {!persistent ? (
          <button
            type="button"
            onClick={skipBanner}
            disabled={isNavigating}
            className="btn btn-ghost"
          >
            {sw ? "Ruka" : "Skip"}
          </button>
        ) : null}
      </div>
      {locationMessage ? <p className="mt-3 text-sm font-semibold text-brand-ink" role="status">{locationMessage}</p> : null}
      {manualOpen ? (
        <div className="soft-panel mt-5 grid gap-4 p-4 sm:grid-cols-2 sm:p-5">
          <label className="grid gap-2">
            <span className="field-label text-sm">{sw ? "Mkoa" : "Region"}</span>
            <select
              value={regionId}
              onChange={async (event) => {
                const nextRegionId = event.target.value;
                setRegionId(nextRegionId);
                setDistrictId("");
                setWardId("");
                setAreaId("");
                setWards([]);
                setAreas([]);
                await loadDistricts(nextRegionId);
              }}
              className="field-input"
            >
              <option value="">{sw ? "Chagua mkoa" : "Choose a region"}</option>
              {regions.map((region) => (
                <option key={region.id} value={region.id}>
                  {region.name}
                </option>
              ))}
            </select>
          </label>
          <label className="grid gap-2">
            <span className="field-label text-sm">{sw ? "Wilaya" : "District"}</span>
            <select
              value={districtId}
              onChange={async (event) => {
                const nextDistrictId = event.target.value;
                setDistrictId(nextDistrictId);
                setWardId("");
                setAreaId("");
                await loadWards(nextDistrictId);
              }}
              className="field-input"
            >
              <option value="">{sw ? "Chagua wilaya" : "Choose a district"}</option>
              {districts.map((district) => (
                <option key={district.id} value={district.id}>
                  {district.name}
                </option>
              ))}
            </select>
          </label>
          {wards.length > 0 ? (
            <label className="grid gap-2">
              <span className="field-label text-sm">{sw ? "Kata" : "Ward"}</span>
              <select
                value={wardId}
                onChange={async (event) => {
                  const nextWardId = event.target.value;
                  setWardId(nextWardId);
                  setAreaId("");
                  await loadAreas(nextWardId || districtId);
                }}
                className="field-input"
              >
                <option value="">{sw ? "Kata (si lazima)" : "Ward (optional)"}</option>
                {wards.map((ward) => (
                  <option key={ward.id} value={ward.id}>
                    {ward.name}
                  </option>
                ))}
              </select>
            </label>
          ) : null}
          <label className="grid gap-2">
            <span className="field-label text-sm">{sw ? "Eneo" : "Area"}</span>
            <select
              value={areaId}
              onChange={(event) => setAreaId(event.target.value)}
              className="field-input"
            >
              <option value="">{sw ? "Eneo (si lazima)" : "Area (optional)"}</option>
              {areas.map((area) => (
                <option key={area.id} value={area.id}>
                  {area.name}
                </option>
              ))}
            </select>
          </label>
          <div className="sm:col-span-2">
            <button
              type="button"
              onClick={applyManualLocation}
              disabled={!regionId || !districtId || isNavigating}
              className="btn btn-success"
            >
              {isNavigating ? (sw ? "Inafungua..." : "Loading...") : (sw ? "Tumia eneo hili" : "Use this area")}
            </button>
          </div>
        </div>
      ) : null}
    </section>
  );
}
