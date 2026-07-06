"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";

import { StatusPill } from "@/components/status-pill";

type LocationOption = { id: string; name: string };

export function LocationBanner({
  visibleByDefault,
  regions,
}: {
  visibleByDefault: boolean;
  regions: LocationOption[];
}) {
  const router = useRouter();
  const [isNavigating, startTransition] = useTransition();
  const [visible, setVisible] = useState(() => {
    if (typeof window === "undefined") {
      return visibleByDefault;
    }
    const hiddenUntil = window.localStorage.getItem(
      "customer_location_banner_hidden_until",
    );
    if (hiddenUntil && Number(hiddenUntil) > Date.now()) {
      return false;
    }
    return visibleByDefault;
  });
  const [manualOpen, setManualOpen] = useState(false);
  const [regionId, setRegionId] = useState("");
  const [districtId, setDistrictId] = useState("");
  const [wardId, setWardId] = useState("");
  const [areaId, setAreaId] = useState("");
  const [districts, setDistricts] = useState<LocationOption[]>([]);
  const [wards, setWards] = useState<LocationOption[]>([]);
  const [areas, setAreas] = useState<LocationOption[]>([]);

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
      return;
    }
    navigator.geolocation.getCurrentPosition((position) => {
      const baseUrl = buildBaseUrl();
      window.localStorage.setItem(
        "customer_location_banner_hidden_until",
        String(Date.now() + 3 * 24 * 60 * 60 * 1000),
      );
      window.localStorage.removeItem("customer_region_id");
      window.localStorage.removeItem("customer_district_id");
      window.localStorage.removeItem("customer_ward_id");
      window.localStorage.removeItem("customer_area_id");
      window.localStorage.setItem("customer_latitude", String(position.coords.latitude));
      window.localStorage.setItem("customer_longitude", String(position.coords.longitude));
      baseUrl.searchParams.delete("regionId");
      baseUrl.searchParams.delete("districtId");
      baseUrl.searchParams.delete("wardId");
      baseUrl.searchParams.delete("areaId");
      baseUrl.searchParams.set("lat", String(position.coords.latitude));
      baseUrl.searchParams.set("lng", String(position.coords.longitude));
      navigateTo(baseUrl);
    });
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

  if (!visible) {
    return null;
  }

  return (
    <section className="surface-card rounded-[20px] p-5 sm:p-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="max-w-2xl">
          <div className="flex flex-wrap items-center gap-3">
            <p className="eyebrow">Location setup</p>
            <StatusPill label="Private area only" tone="info" />
          </div>
          <h2 className="mt-3 font-heading text-2xl font-semibold text-brand-ink sm:text-3xl">
            Unatafuta mali karibu na ulipo?
          </h2>
          <p className="section-copy mt-3 text-base">
            Chagua eneo lako ili tuanze na listings zinazofaa. KODIMALI inaonyesha
            eneo la jumla tu, si address kamili ya mwenye mali.
          </p>
        </div>
      </div>
      <div className="mt-5 flex flex-wrap gap-3">
        <button
          type="button"
          onClick={useGps}
          disabled={isNavigating}
          className="btn btn-primary"
        >
          Tumia eneo langu
        </button>
        <button
          type="button"
          onClick={() => setManualOpen((value) => !value)}
          disabled={isNavigating}
          className="btn btn-outline"
        >
          Chagua eneo
        </button>
        <button
          type="button"
          onClick={skipBanner}
          disabled={isNavigating}
          className="btn btn-ghost"
        >
          Ruka
        </button>
      </div>
      {manualOpen ? (
        <div className="soft-panel mt-5 grid gap-4 p-4 sm:grid-cols-2 sm:p-5">
          <label className="grid gap-2">
            <span className="field-label text-sm">Region</span>
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
              <option value="">Chagua Region</option>
              {regions.map((region) => (
                <option key={region.id} value={region.id}>
                  {region.name}
                </option>
              ))}
            </select>
          </label>
          <label className="grid gap-2">
            <span className="field-label text-sm">District</span>
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
              <option value="">Chagua District</option>
              {districts.map((district) => (
                <option key={district.id} value={district.id}>
                  {district.name}
                </option>
              ))}
            </select>
          </label>
          {wards.length > 0 ? (
            <label className="grid gap-2">
              <span className="field-label text-sm">Ward</span>
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
                <option value="">Ward si lazima</option>
                {wards.map((ward) => (
                  <option key={ward.id} value={ward.id}>
                    {ward.name}
                  </option>
                ))}
              </select>
            </label>
          ) : null}
          <label className="grid gap-2">
            <span className="field-label text-sm">Area</span>
            <select
              value={areaId}
              onChange={(event) => setAreaId(event.target.value)}
              className="field-input"
            >
              <option value="">Area si lazima</option>
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
              {isNavigating ? "Inafungua..." : "Tumia eneo hili"}
            </button>
          </div>
        </div>
      ) : null}
    </section>
  );
}
