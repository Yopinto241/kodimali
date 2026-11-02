"use client";
import { useEffect, useRef, useState } from "react";
import { useLanguage } from "@/components/language-provider";
import { UiText } from "@/components/ui-text";
import { useNavigate } from "@/components/navigation-progress";
import { getBrowserSupabase } from "@/lib/supabase-browser";
import { browserPreferences } from "@/lib/browser-preferences";
import { applyWardLocation, wardLocation, type WardLocation } from "@/lib/ward-search";
import { revealListingFilterError, validateListingFilterForm } from "@/lib/listing-filter-validation";
import { useHydrated } from "@/lib/use-hydrated";

function position(): Promise<GeolocationPosition> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("Location unavailable")), 16000);
    navigator.geolocation.getCurrentPosition((value) => { clearTimeout(timer); resolve(value); }, (error) => { clearTimeout(timer); reject(error); }, { enableHighAccuracy: false, timeout: 15000, maximumAge: 60000 });
  });
}
export function WardGpsFilter() {
  const navigate = useNavigate();
  const ready = useHydrated();
  const { language } = useLanguage();
  const button = useRef<HTMLButtonElement>(null);
  const dialog = useRef<HTMLDialogElement>(null);
  const generation = useRef(0);
  const [busy, setBusy] = useState(false);
  const [ward, setWard] = useState<WardLocation | null>(null);
  const [error, setError] = useState("");
  useEffect(() => () => { generation.current += 1; }, []);
  function close() { generation.current += 1; setBusy(false); dialog.current?.close(); button.current?.focus(); }
  async function locate() {
    const current = ++generation.current;
    setWard(null); setError(""); setBusy(true); dialog.current?.showModal();
    try {
      if (!navigator.geolocation) throw new Error("Unsupported location");
      const coordinates = (await position()).coords;
      if (current !== generation.current) return;
      const result = await getBrowserSupabase().rpc("resolve_location_hierarchy", { p_latitude: coordinates.latitude, p_longitude: coordinates.longitude } as never).abortSignal(AbortSignal.timeout(10000));
      if (current !== generation.current) return;
      const found = wardLocation(result.data?.[0]);
      if (result.error || !found) throw new Error("Ward unavailable");
      setWard(found);
    } catch { if (current === generation.current) setError("We could not find your ward. Please allow location access or choose manually."); }
    finally { if (current === generation.current) setBusy(false); }
  }
  function apply() {
    if (!ward) return;
    const form = button.current?.closest("form");
    if (form) {
      const problem = validateListingFilterForm(form);
      if (problem) { close(); revealListingFilterError(form, problem); return; }
    }
    const url = new URL(window.location.href);
    if (form) for (const [key, value] of new FormData(form)) {
      if (typeof value !== "string") continue;
      if (value.trim()) url.searchParams.set(key, value.trim()); else url.searchParams.delete(key);
    }
    applyWardLocation(url, ward);
    for (const [key, value] of [["region", ward.region_id], ["district", ward.district_id], ["ward", ward.ward_id]]) browserPreferences.setItem(`customer_${key}_id`, value);
    for (const key of ["area_id", "latitude", "longitude"]) browserPreferences.removeItem(`customer_${key}`);
    close(); navigate(`${url.pathname}${url.search}`);
  }
  return <div className="ward-gps-filter">
    <button type="button" className="listing-location-trigger" disabled={!ready || busy} ref={button} onClick={() => void locate()}><span aria-hidden="true">◎</span><UiText text="Use my location" /></button>
    <dialog ref={dialog} className="listing-location-dialog" aria-label={language === "sw" ? "Eneo la GPS" : "GPS location"} onCancel={() => { generation.current += 1; setBusy(false); }}>
      <div className="listing-location-dialog-content">
        <h2><UiText text="Search the whole ward" /></h2>
        <p><UiText text="GPS suggests a ward. Confirm it or choose your location manually." /></p>
        {busy && <p role="status"><UiText text="Finding your location..." /></p>}
        {error && <p role="alert"><UiText text={error} /></p>}
        {ward && <p className="font-semibold"><UiText text="Suggested ward" />: {ward.ward_name || <UiText text="Ward" />}</p>}
        <div className="listing-location-dialog-actions">
          <button type="button" className="btn btn-outline" onClick={close}><UiText text="Cancel" /></button>
          <button type="button" className="btn btn-outline" onClick={() => { const manual = button.current?.closest("form,section")?.querySelector<HTMLButtonElement>(".listing-location-filter > button"); close(); manual?.click(); }}><UiText text="Choose manually" /></button>
          {ward && <button type="button" className="btn btn-success" onClick={apply}><UiText text="Search this ward" /></button>}
        </div>
      </div>
    </dialog>
  </div>;
}
