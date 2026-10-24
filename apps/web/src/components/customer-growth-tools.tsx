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
  const [loaded, setLoaded] = useState(false);
  const load = useCallback(async (id: string) => {
    const [a,b,c,d,e] = await Promise.all([
      supabase.from("customer_saved_listings").select("listing_id,created_at,listings(title,price_amount,public_location_label)").eq("customer_id", id).order("created_at", { ascending: false }),
      supabase.from("customer_listing_views").select("listing_id,last_viewed_at,view_count,listings(title,price_amount,public_location_label)").eq("customer_id", id).order("last_viewed_at", { ascending: false }).limit(12),
      supabase.from("saved_searches").select("*").eq("user_id", id).order("created_at", { ascending: false }),
      supabase.from("price_alerts").select("*,listings(title,price_amount)").eq("user_id", id).order("created_at", { ascending: false }),
      supabase.from("notification_preferences").select("*").eq("user_id", id).maybeSingle(),
    ]);
    setSaved((a.data as Row[] | null) ?? []); setRecent((b.data as Row[] | null) ?? []); setSearches((c.data as Row[] | null) ?? []); setAlerts((d.data as Row[] | null) ?? []); setPreferences((e.data as Row | null) ?? {}); setLoaded(true);
  }, [supabase]);
  useEffect(() => { void supabase.auth.getUser().then(({data}) => { const id=data.user?.id ?? null; setUserId(id); if(id) void load(id); }); }, [load, supabase]);
  if (!userId) return null;
  async function remove(table: string, idKey: string, id: string) { await supabase.from(table).delete().eq(idKey,id); await load(userId!); }
  async function preference(key: string, value: boolean) { await supabase.from("notification_preferences").upsert({ user_id:userId,[key]:value } as never); await load(userId!); }
  const hasActivity = saved.length + recent.length + searches.length + alerts.length > 0;
  return <section className="mt-8 grid gap-6">
    {!loaded ? <div className="surface-card p-6 text-muted">Inapakia...</div> : null}
    {loaded && !hasActivity ? <div className="surface-card p-6 text-muted">Hakuna shughuli.</div> : null}
    {saved.length > 0 ? <AccountList title="Mali Zilizohifadhiwa" rows={saved} render={(row)=><><Link className="font-bold underline" href={`/listing/${row.listing_id}`}>{title(row)}</Link><button className="text-sm font-bold text-brand-danger" onClick={()=>void remove("customer_saved_listings","listing_id",String(row.listing_id))}>Ondoa</button></>} /> : null}
    {recent.length > 0 ? <AccountList title="Ulizotazama" rows={recent} render={(row)=><><Link className="font-bold underline" href={`/listing/${row.listing_id}`}>{title(row)}</Link><span className="text-xs text-muted">Mara {String(row.view_count)}</span></>} /> : null}
    {searches.length > 0 ? <AccountList title="Utafutaji Uliohifadhiwa" rows={searches} render={(row)=><><p className="font-bold">{String(row.name)}</p><button className="text-sm font-bold text-brand-danger" onClick={()=>void remove("saved_searches","id",String(row.id))}>Futa</button></>} /> : null}
    {alerts.length > 0 ? <AccountList title="Taarifa za Bei" rows={alerts} render={(row)=><><Link className="font-bold underline" href={`/listing/${row.listing_id}`}>{title(row)}</Link><button className="text-sm font-bold text-brand-danger" onClick={()=>void remove("price_alerts","id",String(row.id))}>Futa</button></>} /> : null}
    <details className="surface-card p-6"><summary className="cursor-pointer font-heading text-xl font-semibold">Mipangilio ya Arifa</summary><div className="mt-4 grid gap-3 sm:grid-cols-2">{[["chat_enabled","Ujumbe"],["requests_enabled","Maombi"],["payments_enabled","Malipo"],["reminders_enabled","Miadi"],["promotions_enabled","Matangazo"]].map(([key,label])=><label className="flex justify-between rounded-xl border border-brand-border p-4" key={key}><span className="font-semibold">{label}</span><input type="checkbox" checked={preferences[key] !== false} onChange={(e)=>void preference(key,e.target.checked)} /></label>)}</div></details>
  </section>;
}
function title(row: Row) { const value = row.listings; const listing = Array.isArray(value)?value[0]:value; return listing&&typeof listing==="object"?String((listing as Row).title??"Listing"):"Listing"; }
function AccountList({title,rows,render}:{title:string;rows:Row[];render:(row:Row)=>React.ReactNode}) { return <div className="surface-card p-6"><h2 className="font-heading text-2xl font-semibold">{title}</h2><div className="mt-4 grid gap-3">{rows.map((row,index)=><article className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-brand-border p-4" key={String(row.id??row.listing_id??index)}>{render(row)}</article>)}</div></div>; }
