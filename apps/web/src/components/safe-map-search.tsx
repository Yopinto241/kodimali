"use client";

import { useState } from "react";

export function SafeMapSearch() {
  const [coords, setCoords] = useState<{ lat: number; lng: number } | null>(null);
  const [message, setMessage] = useState("");
  function locate() {
    if (!navigator.geolocation) { setMessage("Location is not supported by this browser."); return; }
    setMessage("Requesting your location...");
    navigator.geolocation.getCurrentPosition((position) => { setCoords({ lat: position.coords.latitude, lng: position.coords.longitude }); setMessage("Location ready. Exact property coordinates remain private."); }, () => setMessage("Location permission was not granted."), { enableHighAccuracy: false, timeout: 10000 });
  }
  const mapUrl = coords ? `https://www.openstreetmap.org/export/embed.html?bbox=${coords.lng - .04}%2C${coords.lat - .04}%2C${coords.lng + .04}%2C${coords.lat + .04}&layer=mapnik&marker=${coords.lat}%2C${coords.lng}` : null;
  return <section className="surface-card p-6"><div className="flex flex-wrap items-center justify-between gap-4"><div><h2 className="font-heading text-2xl font-semibold">Search near your device</h2><p className="mt-2 text-sm text-muted">Your location is used only to rank public listing areas nearby.</p></div><button className="btn btn-success" onClick={locate}>Use my location</button></div>{message ? <p className="mt-4 rounded-xl bg-brand-info-soft p-3 text-sm">{message}</p> : null}{mapUrl ? <><iframe className="mt-5 h-[420px] w-full rounded-2xl border border-brand-border" title="Approximate search map" src={mapUrl} loading="lazy" /><a className="btn btn-primary mt-5" href={`/listings?lat=${coords!.lat}&lng=${coords!.lng}`}>View nearby listings</a></> : null}</section>;
}
