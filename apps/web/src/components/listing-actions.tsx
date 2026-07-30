"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { getBrowserSupabase } from "@/lib/supabase-browser";

const comparisonKey = "kodimali-comparison-listings";

export function ListingActions({ listingId }: { listingId: string }) {
  const supabase = useMemo(() => getBrowserSupabase(), []);
  const [saved, setSaved] = useState(false);
  const [compared, setCompared] = useState(false);
  const [message, setMessage] = useState("");

  useEffect(() => {
    const ids = JSON.parse(localStorage.getItem(comparisonKey) || "[]") as string[];
    queueMicrotask(() => setCompared(ids.includes(listingId)));
    void supabase.auth.getUser().then(async ({ data }) => {
      if (!data.user) return;
      const result = await supabase.from("customer_saved_listings").select("listing_id")
        .eq("customer_id", data.user.id).eq("listing_id", listingId).maybeSingle();
      setSaved(Boolean(result.data));
    });
  }, [listingId, supabase]);

  async function toggleSaved() {
    const { data } = await supabase.auth.getUser();
    if (!data.user) {
      setMessage("Sign in from Customer Account to synchronize saved listings.");
      return;
    }
    const next = !saved;
    const result = await supabase.rpc("set_listing_saved", {
      p_listing_id: listingId, p_saved: next,
    } as never);
    if (result.error) setMessage(result.error.message);
    else { setSaved(next); setMessage(next ? "Listing saved." : "Listing removed."); }
  }

  async function createPriceAlert() {
    const { data } = await supabase.auth.getUser();
    if (!data.user) { setMessage("Sign in from Customer Account to create a price alert."); return; }
    const result = await supabase.from("price_alerts").upsert({ user_id: data.user.id, listing_id: listingId, is_active: true } as never, { onConflict: "user_id,listing_id" });
    setMessage(result.error?.message ?? "Price-drop alert enabled.");
  }

  function toggleCompared() {
    const current = JSON.parse(localStorage.getItem(comparisonKey) || "[]") as string[];
    const next = current.includes(listingId)
      ? current.filter((id) => id !== listingId)
      : [...current, listingId].slice(-4);
    localStorage.setItem(comparisonKey, JSON.stringify(next));
    setCompared(next.includes(listingId));
    setMessage(next.includes(listingId) ? "Added to comparison." : "Removed from comparison.");
  }

  return <div className="mt-4" onClick={(event) => event.stopPropagation()}>
    <div className="flex flex-wrap gap-2">
      <button type="button" className="btn btn-outline !min-h-9 !px-3 !py-2 text-xs" onClick={() => void toggleSaved()}>
        {saved ? "Saved" : "Save"}
      </button>
      <button type="button" className="btn btn-outline !min-h-9 !px-3 !py-2 text-xs" onClick={toggleCompared}>
        {compared ? "Comparing" : "Compare"}
      </button>
      <button type="button" className="btn btn-outline !min-h-9 !px-3 !py-2 text-xs" onClick={() => void createPriceAlert()}>Price alert</button>
      <Link href="/compare" className="btn btn-ghost !min-h-9 !px-3 !py-2 text-xs">View comparison</Link>
    </div>
    {message ? <p className="mt-2 text-xs text-muted" role="status">{message}</p> : null}
  </div>;
}

export function ListingViewRecorder({ listingId }: { listingId: string }) {
  const supabase = useMemo(() => getBrowserSupabase(), []);
  useEffect(() => {
    const recent = JSON.parse(localStorage.getItem("kodimali-recent-listings") || "[]") as string[];
    localStorage.setItem("kodimali-recent-listings", JSON.stringify([listingId, ...recent.filter((id) => id !== listingId)].slice(0, 12)));
    void supabase.auth.getUser().then(({ data }) => {
      if (data.user) void supabase.rpc("record_listing_view", { p_listing_id: listingId } as never);
    });
    void supabase.rpc("track_business_event", { p_event_type: "listing_view", p_listing_id: listingId, p_metadata: { surface: "website" } } as never);
  }, [listingId, supabase]);
  return null;
}
