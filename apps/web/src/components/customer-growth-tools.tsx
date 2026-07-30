"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { getBrowserSupabase } from "@/lib/supabase-browser";

type Row = Record<string, unknown>;
export function CustomerGrowthTools() {
  const supabase = useMemo(() => getBrowserSupabase(), []);
  const [userId, setUserId] = useState<string | null>(null);
  const [saved, setSaved] = useState<Row[]>([]); const [recent, setRecent] = useState<Row[]>([]);
  const [searches, setSearches] = useState<Row[]>([]); const [alerts, setAlerts] = useState<Row[]>([]);
  const [preferences, setPreferences] = useState<Row>({});
  const load = useCallback(async (id: string) => {
    const [a,b,c,d,e] = await Promise.all([
      supabase.from("customer_saved_listings").select("listing_id,created_at,listings(title,price_amount,public_location_label)").eq("customer_id", id).order("created_at", { ascending: false }),
      supabase.from("customer_listing_views").select("listing_id,last_viewed_at,view_count,listings(title,price_amount,public_location_label)").eq("customer_id", id).order("last_viewed_at", { ascending: false }).limit(12),
      supabase.from("saved_searches").select("*").eq("user_id", id).order("created_at", { ascending: false }),
      supabase.from("price_alerts").select("*,listings(title,price_amount)").eq("user_id", id).order("created_at", { ascending: false }),
      supabase.from("notification_preferences").select("*").eq("user_id", id).maybeSingle(),
    ]);
    setSaved((a.data as Row[] | null) ?? []); setRecent((b.data as Row[] | null) ?? []); setSearches((c.data as Row[] | null) ?? []); setAlerts((d.data as Row[] | null) ?? []); setPreferences((e.data as Row | null) ?? {});
  }, [supabase]);
  useEffect(() => { void supabase.auth.getUser().then(({data}) => { const id=data.user?.id ?? null; setUserId(id); if(id) void load(id); }); }, [load, supabase]);
  if (!userId) return null;
  async function remove(table: string, idKey: string, id: string) { await supabase.from(table).delete().eq(idKey,id); await load(userId!); }
  async function preference(key: string, value: boolean) { await supabase.from("notification_preferences").upsert({ user_id:userId,[key]:value } as never); await load(userId!); }
  return <section className="mt-8 grid gap-6">
    <AccountList title="Saved listings" rows={saved} empty="Save listings from the marketplace to see them here." render={(row)=><><Link className="font-bold underline" href={`/listing/${row.listing_id}`}>{title(row)}</Link><button className="text-sm font-bold text-brand-danger" onClick={()=>void remove("customer_saved_listings","listing_id",String(row.listing_id))}>Remove</button></>} />
    <AccountList title="Recently viewed" rows={recent} empty="Listings you view while signed in appear here." render={(row)=><><Link className="font-bold underline" href={`/listing/${row.listing_id}`}>{title(row)}</Link><span className="text-xs text-muted">Viewed {String(row.view_count)} times</span></>} />
    <AccountList title="Saved searches and alerts" rows={searches} empty="Save a marketplace search to receive matching-listing alerts." render={(row)=><><div><p className="font-bold">{String(row.name)}</p><p className="text-xs text-muted">Alerts {row.alerts_enabled ? "enabled" : "disabled"}</p></div><button className="text-sm font-bold text-brand-danger" onClick={()=>void remove("saved_searches","id",String(row.id))}>Delete</button></>} />
    <AccountList title="Price alerts" rows={alerts} empty="Price alerts you create will appear here." render={(row)=><><Link className="font-bold underline" href={`/listing/${row.listing_id}`}>{title(row)}</Link><button className="text-sm font-bold text-brand-danger" onClick={()=>void remove("price_alerts","id",String(row.id))}>Delete</button></>} />
    <div className="surface-card p-6"><h2 className="font-heading text-2xl font-semibold">Notification preferences</h2><div className="mt-4 grid gap-3 sm:grid-cols-2">{[["chat_enabled","Chat messages"],["requests_enabled","Requests"],["payments_enabled","Payments"],["reminders_enabled","Viewing reminders"],["promotions_enabled","Promotions and price alerts"]].map(([key,label])=><label className="flex justify-between rounded-xl border border-brand-border p-4" key={key}><span className="font-semibold">{label}</span><input type="checkbox" checked={preferences[key] !== false} onChange={(e)=>void preference(key,e.target.checked)} /></label>)}</div></div>
  </section>;
}
function title(row: Row) { const value = row.listings; const listing = Array.isArray(value)?value[0]:value; return listing&&typeof listing==="object"?String((listing as Row).title??"Listing"):"Listing"; }
function AccountList({title,rows,empty,render}:{title:string;rows:Row[];empty:string;render:(row:Row)=>React.ReactNode}) { return <div className="surface-card p-6"><h2 className="font-heading text-2xl font-semibold">{title}</h2><div className="mt-4 grid gap-3">{rows.length===0?<p className="text-muted">{empty}</p>:rows.map((row,index)=><article className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-brand-border p-4" key={String(row.id??row.listing_id??index)}>{render(row)}</article>)}</div></div>; }
