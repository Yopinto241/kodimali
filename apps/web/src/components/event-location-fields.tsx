"use client";

import { useEffect, useState } from "react";
import { useLanguage } from "@/components/language-provider";
import { getBrowserSupabase } from "@/lib/supabase-browser";

type Option = { id: string; name: string };

export function EventLocationFields({
  value,
  onChange,
  inputName,
  required = false,
}: {
  value: string;
  onChange: (locationId: string) => void;
  inputName?: string;
  required?: boolean;
}) {
  const { language } = useLanguage();
  const sw = language === "sw";
  const [regions, setRegions] = useState<Option[]>([]);
  const [districts, setDistricts] = useState<Option[]>([]);
  const [wards, setWards] = useState<Option[]>([]);
  const [areas, setAreas] = useState<Option[]>([]);
  const [regionId, setRegionId] = useState("");
  const [districtId, setDistrictId] = useState("");
  const [wardId, setWardId] = useState("");
  const [areaId, setAreaId] = useState("");

  async function children(type: string, parentId: string) {
    if (!parentId) return [];
    const response = await fetch(
      `/api/locations?locationType=${type}&parentId=${parentId}`,
    );
    return response.ok ? ((await response.json()) as Option[]) : [];
  }

  useEffect(() => {
    let active = true;
    void (async () => {
      const { data } = await getBrowserSupabase()
        .from("locations")
        .select("id")
        .eq("location_type", "country")
        .eq("is_active", true)
        .limit(1)
        .maybeSingle();
      const country = data as { id: string } | null;
      if (!active || !country?.id) return;
      const nextRegions = await children("region", String(country.id));
      if (!active) return;
      setRegions(nextRegions);
      const savedRegion =
        window.localStorage.getItem("customer_region_id") ?? "";
      const savedDistrict =
        window.localStorage.getItem("customer_district_id") ?? "";
      const savedWard = window.localStorage.getItem("customer_ward_id") ?? "";
      const savedArea = window.localStorage.getItem("customer_area_id") ?? "";
      if (!value && savedRegion) {
        setRegionId(savedRegion);
        const nextDistricts = await children("district", savedRegion);
        if (!active) return;
        setDistricts(nextDistricts);
        if (savedDistrict) {
          setDistrictId(savedDistrict);
          const [nextWards, districtAreas] = await Promise.all([
            children("ward", savedDistrict),
            children("area", savedDistrict),
          ]);
          if (!active) return;
          setWards(nextWards);
          setAreas(districtAreas);
          if (savedWard) {
            setWardId(savedWard);
            setAreas(await children("area", savedWard));
          }
          if (savedArea) setAreaId(savedArea);
          onChange(savedArea || savedWard || savedDistrict || savedRegion);
        } else onChange(savedRegion);
      }
    })();
    return () => {
      active = false;
    };
    // The saved location should be restored once, not whenever the parent rerenders.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function choose(
    region: string,
    district: string,
    ward: string,
    area: string,
  ) {
    const values = {
      region: region,
      district: district,
      ward: ward,
      area: area,
    };
    for (const [level, id] of Object.entries(values)) {
      const key = `customer_${level}_id`;
      if (id) window.localStorage.setItem(key, id);
      else window.localStorage.removeItem(key);
    }
    onChange(area || ward || district || region);
  }

  return (
    <div className="event-location-grid grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
      {inputName ? (
        <input type="hidden" name={inputName} value={value} />
      ) : null}
      <label className="grid gap-2 text-sm font-semibold">
        <span>{sw ? "Mkoa" : "Region"}</span>
        <select
          className="field-input"
          value={regionId}
          required={required}
          onChange={async (event) => {
            const id = event.target.value;
            setRegionId(id);
            setDistrictId("");
            setWardId("");
            setAreaId("");
            setWards([]);
            setAreas([]);
            setDistricts(await children("district", id));
            choose(id, "", "", "");
          }}
        >
          <option value="">{sw ? "Chagua mkoa" : "Choose region"}</option>
          {regions.map((item) => (
            <option key={item.id} value={item.id}>
              {item.name}
            </option>
          ))}
        </select>
      </label>
      <label className="grid gap-2 text-sm font-semibold">
        <span>{sw ? "Wilaya" : "District"}</span>
        <select
          className="field-input"
          value={districtId}
          required={required}
          disabled={!regionId}
          onChange={async (event) => {
            const id = event.target.value;
            setDistrictId(id);
            setWardId("");
            setAreaId("");
            const [nextWards, nextAreas] = await Promise.all([
              children("ward", id),
              children("area", id),
            ]);
            setWards(nextWards);
            setAreas(nextAreas);
            choose(regionId, id, "", "");
          }}
        >
          <option value="">{sw ? "Chagua wilaya" : "Choose district"}</option>
          {districts.map((item) => (
            <option key={item.id} value={item.id}>
              {item.name}
            </option>
          ))}
        </select>
      </label>
      <label className="grid gap-2 text-sm font-semibold">
        <span>{sw ? "Kata" : "Ward"}</span>
        <select
          className="field-input"
          value={wardId}
          disabled={!districtId}
          onChange={async (event) => {
            const id = event.target.value;
            setWardId(id);
            setAreaId("");
            setAreas(await children("area", id || districtId));
            choose(regionId, districtId, id, "");
          }}
        >
          <option value="">
            {sw ? "Kata (si lazima)" : "Ward (optional)"}
          </option>
          {wards.map((item) => (
            <option key={item.id} value={item.id}>
              {item.name}
            </option>
          ))}
        </select>
      </label>
      <label className="grid gap-2 text-sm font-semibold">
        <span>{sw ? "Eneo" : "Area"}</span>
        <select
          className="field-input"
          value={areaId}
          disabled={!districtId}
          onChange={(event) => {
            const id = event.target.value;
            setAreaId(id);
            choose(regionId, districtId, wardId, id);
          }}
        >
          <option value="">
            {sw ? "Eneo (si lazima)" : "Area (optional)"}
          </option>
          {areas.map((item) => (
            <option key={item.id} value={item.id}>
              {item.name}
            </option>
          ))}
        </select>
      </label>
    </div>
  );
}
