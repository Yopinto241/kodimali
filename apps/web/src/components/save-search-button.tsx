"use client";

import { useMemo, useState } from "react";
import { getBrowserSupabase } from "@/lib/supabase-browser";

export function SaveSearchButton({ filters }: { filters: Record<string, string> }) {
  const supabase = useMemo(() => getBrowserSupabase(), []);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  async function save() {
    setBusy(true);
    const { data } = await supabase.auth.getUser();
    if (!data.user) { setMessage("Sign in through Customer Account to save searches."); setBusy(false); return; }
    const name = [filters.q, filters.category].filter(Boolean).join(" · ") || "Marketplace search";
    const result = await supabase.from("saved_searches").insert({ user_id: data.user.id, name, filters, alerts_enabled: true } as never);
    setMessage(result.error ? result.error.message : "Search saved. Matching-listing alerts are enabled.");
    setBusy(false);
  }
  return <div><button className="btn btn-outline" disabled={busy} onClick={() => void save()}>{busy ? "Saving..." : "Save this search"}</button>{message ? <p className="mt-2 text-xs text-muted" role="status">{message}</p> : null}</div>;
}
