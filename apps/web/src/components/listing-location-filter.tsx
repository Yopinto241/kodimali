"use client";
import { useEffect, useId, useRef, useState } from "react";
import { revealListingFilterError, validateListingFilterForm } from "@/lib/listing-filter-validation";
import { UiText } from "@/components/ui-text";
import { browserPreferences } from "@/lib/browser-preferences";
import { useNavigate } from "@/components/navigation-progress";
import { useLanguage } from "@/components/language-provider";
import { useHydrated } from "@/lib/use-hydrated";
type Option = { id: string; name: string };
const keys = ["regionId", "districtId", "wardId", "areaId"];
const names = ["Region", "District", "Ward", "Area"];
const types = ["region", "district", "ward", "area"];
export function ListingLocationFilter({ regions, initialRegionId = "", initialDistrictId = "", initialWardId = "", initialAreaId = "", initialRegionName = "", initialDistrictName = "", initialWardName = "", initialAreaName = "" }: {
  regions: Option[]; initialRegionId?: string; initialDistrictId?: string; initialWardId?: string; initialAreaId?: string;
  initialRegionName?: string; initialDistrictName?: string; initialWardName?: string; initialAreaName?: string;
}) {
  const navigate = useNavigate();
  const ready = useHydrated();
  const titleId = useId();
  const { language } = useLanguage();
  const dialog = useRef<HTMLDialogElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const cache = useRef(new Map<string, Option[]>());
  const applied = [initialRegionId, initialDistrictId, initialWardId, initialAreaId];
  const [ids, setIds] = useState(applied);
  const [options, setOptions] = useState<Option[][]>([regions, [], [], []]);
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [retry, setRetry] = useState(0);
  const [saved, setSaved] = useState<string[]>([]);
  const [region, district, ward] = ids;
  useEffect(() => { queueMicrotask(() => setSaved(types.map((type) => browserPreferences.getItem(`customer_${type}_id`) ?? ""))); }, []);
  useEffect(() => {
    if (!open) return;
    const controller = new AbortController();
    const signal = AbortSignal.any([controller.signal, AbortSignal.timeout(10000)]);
    const parents = [region, district, ward];
    queueMicrotask(() => { if (!controller.signal.aborted) { setLoading(true); setError(""); } });
    Promise.all(parents.map(async (parent, index) => {
      if (!parent) return [];
      const key = `${types[index + 1]}:${parent}`;
      const cached = cache.current.get(key);
      if (cached) return cached;
      const response = await fetch(`/api/locations?locationType=${types[index + 1]}&parentId=${encodeURIComponent(parent)}`, { signal });
      if (!response.ok) throw new Error("Could not load locations. Please try again.");
      const rows = await response.json() as Option[];
      if (!Array.isArray(rows)) throw new Error("Could not load locations. Please try again.");
      cache.current.set(key, rows); return rows;
    })).then((children) => { if (!controller.signal.aborted) {
      const allOptions = [regions, ...children];
      setOptions(allOptions);
      setIds((current) => {
        const invalid = current.findIndex((id, index) => Boolean(id) && !allOptions[index].some((row) => row.id === id));
        return invalid < 0 ? current : current.map((id, index) => index < invalid ? id : "");
      });
      setLoading(false);
    } })
      .catch(() => { if (!controller.signal.aborted) { setError("Could not load locations. Please try again."); setLoading(false); } });
    return () => controller.abort();
  }, [open, region, district, ward, regions, retry]);
  const appliedNames = [initialRegionName || regions.find((row) => row.id === initialRegionId)?.name, initialDistrictName, initialWardName, initialAreaName];
  const label = appliedNames.filter(Boolean).slice(-1)[0] || (applied.some(Boolean) ? "Location selected" : "Any location");
  function close() { dialog.current?.close(); setOpen(false); trigger.current?.focus(); }
  function show() { setIds(applied); setError(""); setOpen(true); dialog.current?.showModal(); }
  function apply(next: string[]) {
    const url = new URL(window.location.href);
    const form = trigger.current?.closest("form");
    if (form) {
      const problem = validateListingFilterForm(form);
      if (problem) { close(); revealListingFilterError(form, problem); return; }
    }
    if (form) for (const [key, value] of new FormData(form)) {
      if (typeof value !== "string") continue;
      if (value.trim()) url.searchParams.set(key, value.trim()); else url.searchParams.delete(key);
    }
    for (const key of ["page", "lat", "lng"]) url.searchParams.delete(key);
    keys.forEach((key, index) => {
      if (next[index]) url.searchParams.set(key, next[index]); else url.searchParams.delete(key);
      const preference = `customer_${types[index]}_id`;
      if (next[index]) browserPreferences.setItem(preference, next[index]); else browserPreferences.removeItem(preference);
    });
    browserPreferences.removeItem("customer_latitude"); browserPreferences.removeItem("customer_longitude");
    close(); navigate(`${url.pathname}${url.search}`);
  }
  return <div className="listing-location-filter">
    <button type="button" ref={trigger} className="listing-location-trigger" disabled={!ready} aria-haspopup="dialog" aria-expanded={open} onClick={show}><span aria-hidden="true">⌖</span><span><UiText text={label} /></span><span aria-hidden="true">⌄</span></button>
    <dialog ref={dialog} className="listing-location-dialog" aria-labelledby={titleId} onCancel={() => { setOpen(false); }} onClick={(event) => { if (event.target === event.currentTarget) close(); }}>
      <div className="listing-location-dialog-content"><h2 id={titleId}><UiText text="Choose location" /></h2><p><UiText text="Choose only the location levels you need. Other filters stay unchanged." /></p>
        {names.map((name, index) => <label key={name}><UiText text={name} /><select aria-label={language === "sw" ? ["Mkoa", "Wilaya", "Kata", "Eneo"][index] : name} value={ids[index]} disabled={index > 0 && (!ids[index - 1] || loading || options[index].length === 0)} onChange={(event) => {
          const value = event.target.value; setIds((current) => current.map((id, level) => level < index ? id : level === index ? value : "")); setOptions((current) => current.map((rows, level) => level <= index ? rows : []));
        }}><option value=""><UiText text={["All regions", "All districts", "All wards", "All areas"][index]} /></option>{options[index].map((row) => <option key={row.id} value={row.id}>{row.name}</option>)}</select>{index > 0 && ids[index - 1] && !loading && !error && options[index].length === 0 && <span className="text-sm font-normal"><UiText text={["", "No districts are saved here. You can search using the selected region.", "No wards are saved here. You can search using the selected district.", "No areas are saved here. You can search using the selected ward."][index]} /></span>}</label>)}
        {loading && <p role="status"><UiText text="Loading..." /></p>}
        {error && <div role="alert"><UiText text={error} /><p><UiText text="You can retry or search using the location already selected." /></p><button type="button" onClick={() => setRetry((value) => value + 1)}><UiText text="Retry" /></button></div>}
        {!applied.some(Boolean) && saved[0] && <button type="button" className="btn btn-outline" onClick={() => setIds(saved)}><UiText text="Use saved location" /></button>}
        <div className="listing-location-dialog-actions"><button type="button" className="btn btn-outline" onClick={() => apply(["", "", "", ""])}><UiText text="All locations" /></button><button type="button" className="btn btn-outline" onClick={close}><UiText text="Cancel" /></button><button type="button" className="btn btn-success" disabled={loading} onClick={() => apply(ids)}><UiText text="Show results" /></button></div>
      </div>
    </dialog>
  </div>;
}
