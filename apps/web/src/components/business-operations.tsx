"use client";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { getBrowserSupabase } from "@/lib/supabase-browser";

type Row = Record<string, unknown>;
const switches = [
  ["contact_payments_enabled", "Contact number payment"],
  ["chat_payments_enabled", "Chat access payment"],
  ["agent_listing_payments_enabled", "Listing publication payment"],
  ["subscription_payments_enabled", "Subscription payment"],
  ["listing_boost_payments_enabled", "Featured campaign payment"],
] as const;

export function BusinessOperations({ role, agentId }: { role: "admin" | "agent"; agentId: string | null }) {
  const supabase = useMemo(() => getBrowserSupabase(), []);
  const [dashboard, setDashboard] = useState<Row>({});
  const [settings, setSettings] = useState<Row>({});
  const [plans, setPlans] = useState<Row[]>([]);
  const [payments, setPayments] = useState<Row[]>([]);
  const [boosts, setBoosts] = useState<Row[]>([]);
  const [risks, setRisks] = useState<Row[]>([]);
  const [refunds, setRefunds] = useState<Row[]>([]);
  const [receipts, setReceipts] = useState<Row[]>([]);
  const [campaignPerformance, setCampaignPerformance] = useState<Row[]>([]);
  const [listings, setListings] = useState<Row[]>([]);
  const [phone, setPhone] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");

  const load = useCallback(async () => {
    setMessage("");
    if (role === "admin") {
      const [analytics, config, paymentRows, boostRows, riskRows, refundRows, performanceRows] = await Promise.all([
        supabase.rpc("get_admin_business_analytics", { p_days: 30 } as never),
        supabase.from("marketplace_settings").select("*").eq("id", true).maybeSingle(),
        supabase.from("agent_commercial_payments").select("id, product_type, requested_amount, payment_status, created_at, agents(business_name)").order("created_at", { ascending: false }).limit(50),
        supabase.from("listing_boosts").select("id, listing_id, placement, duration_days, amount_tzs, status, starts_at, ends_at, listings(title), agents(business_name)").order("created_at", { ascending: false }).limit(50),
        supabase.from("platform_risk_flags").select("*").order("created_at", { ascending: false }).limit(50),
        supabase.from("payment_refunds").select("*").order("created_at", { ascending: false }).limit(50),
        supabase.rpc("get_platform_promotion_performance", { p_days: 30 } as never),
      ]);
      setDashboard((analytics.data as Row | null) ?? {}); setSettings((config.data as Row | null) ?? {});
      setPayments((paymentRows.data as Row[] | null) ?? []); setBoosts((boostRows.data as Row[] | null) ?? []);
      setRisks((riskRows.data as Row[] | null) ?? []); setRefunds((refundRows.data as Row[] | null) ?? []);
      setCampaignPerformance((performanceRows.data as Row[] | null) ?? []);
    } else {
      const [summary, planRows, boostRows, receiptRows, listingRows] = await Promise.all([
        supabase.rpc("get_my_agent_business_dashboard"),
        supabase.from("agent_subscription_plans").select("*").eq("is_active", true).order("monthly_price_tzs"),
        supabase.from("listing_boosts").select("*, listings(title)").order("created_at", { ascending: false }),
        supabase.from("payment_receipts").select("*").order("issued_at", { ascending: false }).limit(50),
        supabase.from("listings").select("id,title,status").eq("agent_id", agentId ?? "").order("created_at", { ascending: false }),
      ]);
      setDashboard((summary.data as Row | null) ?? {}); setPlans((planRows.data as Row[] | null) ?? []);
      setBoosts((boostRows.data as Row[] | null) ?? []); setReceipts((receiptRows.data as Row[] | null) ?? []); setListings((listingRows.data as Row[] | null) ?? []);
    }
  }, [agentId, role, supabase]);

  useEffect(() => { queueMicrotask(() => void load()); }, [load]);

  async function toggle(key: string, next: boolean) {
    if (!window.confirm(`${next ? "Require payment" : "Make free"} for this service? This affects every app and remains active after logout.`)) return;
    setBusy(true); const result = await supabase.from("marketplace_settings").upsert({ id: true, [key]: next } as never);
    setMessage(result.error?.message ?? "Payment setting saved globally."); setBusy(false); await load();
  }

  async function commercialPayment(productType: "subscription" | "listing_boost", id: string) {
    if (phone.trim().length < 8) { setMessage("Enter the agent payment phone number first."); return; }
    setBusy(true);
    const result = await supabase.functions.invoke("create-agent-commercial-payment", { body: { product_type: productType, phone_number: phone.trim(), ...(productType === "subscription" ? { plan_id: id } : { listing_boost_id: id }) } });
    setMessage(result.error?.message ?? String((result.data as Row | null)?.message ?? "Payment request sent. Confirm it on the phone.")); setBusy(false); await load();
  }

  async function createBoost(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); const data = new FormData(event.currentTarget);
    const listingId = String(data.get("listing")); const placement = String(data.get("placement")); const duration = Number(data.get("duration"));
    const amount = duration === 3 ? 5000 : duration === 7 ? 10000 : 30000;
    setBusy(true); const result = await supabase.from("listing_boosts").insert({ listing_id: listingId, agent_id: agentId, placement, duration_days: duration, amount_tzs: amount } as never).select("id").single();
    if (result.error) setMessage(result.error.message); else { setMessage("Campaign created. Complete payment to activate it."); await commercialPayment("listing_boost", String((result.data as Row).id)); }
    setBusy(false); await load();
  }

  async function update(table: string, id: string, status: string) {
    if (!window.confirm(`Change this record to ${status}?`)) return;
    setBusy(true); const result = await supabase.from(table).update({ status, ...(status === "resolved" ? { resolved_at: new Date().toISOString() } : {}) } as never).eq("id", id);
    setMessage(result.error?.message ?? "Operation completed."); setBusy(false); await load();
  }

  return <div className="grid gap-6">
    <section className="surface-card p-6"><h2 className="font-heading text-3xl font-semibold">{role === "admin" ? "Business operations" : "Agent business centre"}</h2><p className="mt-2 text-muted">Live Supabase analytics and commercial workflows.</p><div className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">{Object.entries(dashboard).filter(([, value]) => typeof value !== "object").slice(0, 12).map(([key, value]) => <div className="soft-panel p-4" key={key}><p className="text-xs font-bold uppercase text-muted">{key.replaceAll("_", " ")}</p><p className="mt-2 text-xl font-bold">{String(value ?? 0)}</p></div>)}</div></section>
    {message ? <p className="rounded-xl bg-brand-info-soft p-4" role="status">{message}</p> : null}
    {role === "admin" ? <>
      <section className="surface-card p-6"><h2 className="font-heading text-2xl font-semibold">Global payment switches</h2><p className="mt-2 text-sm text-muted">These database settings persist across devices and sessions.</p><div className="mt-5 grid gap-3">{switches.map(([key, label]) => <label className="flex items-center justify-between gap-4 rounded-xl border border-brand-border p-4" key={key}><span><strong>{label}</strong><span className="block text-xs text-muted">{settings[key] === true ? "Payment required" : "Currently free"}</span></span><input type="checkbox" checked={settings[key] === true} disabled={busy} onChange={(e) => void toggle(key, e.target.checked)} /></label>)}</div></section>
      <OperationList title="Commercial payments" rows={payments} />
      <OperationList title="Sponsored campaign performance (30 days)" rows={campaignPerformance.map((row) => ({ ...row, id: row.promotion_id, status: `${row.impressions} impressions · ${row.clicks} clicks · ${row.click_through_rate}% CTR` }))} />
      <OperationList title="Featured campaigns" rows={boosts} actions={(row) => row.status === "pending" ? <button className="btn btn-success" onClick={() => void update("listing_boosts", String(row.id), "active")}>Approve</button> : null} />
      <OperationList title="Risk and fraud flags" rows={risks} actions={(row) => <button className="btn btn-outline" onClick={() => void update("platform_risk_flags", String(row.id), "resolved")}>Resolve</button>} />
      <OperationList title="Refund requests" rows={refunds} actions={(row) => <><button className="btn btn-success" onClick={() => void update("payment_refunds", String(row.id), "approved")}>Approve</button><button className="btn btn-outline" onClick={() => void update("payment_refunds", String(row.id), "rejected")}>Reject</button></>} />
    </> : <>
      <section className="surface-card p-6"><h2 className="font-heading text-2xl font-semibold">Choose a subscription</h2><label className="field-label mt-4">Payment phone<input className="field-input mt-2" value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="255..." /></label><div className="mt-5 grid gap-4 md:grid-cols-2">{plans.map((plan) => <article className="soft-panel p-5" key={String(plan.id)}><h3 className="font-heading text-2xl font-semibold">{String(plan.name)}</h3><p className="mt-2 text-xl font-bold">TZS {String(plan.monthly_price_tzs)} / month</p><p className="mt-2 text-sm text-muted">{plan.listing_limit == null ? "Unlimited listings" : `${String(plan.listing_limit)} listings`} · Publication fee TZS {String(plan.publication_fee_tzs)}</p><button disabled={busy} className="btn btn-success mt-4" onClick={() => void commercialPayment("subscription", String(plan.id))}>Select {String(plan.name)}</button></article>)}</div></section>
      <section className="surface-card p-6"><h2 className="font-heading text-2xl font-semibold">Promote a listing</h2><form className="mt-5 grid gap-4 sm:grid-cols-3" onSubmit={(e) => void createBoost(e)}><select className="field-input" name="listing" required><option value="">Select listing</option>{listings.map((row) => <option key={String(row.id)} value={String(row.id)}>{String(row.title)}</option>)}</select><select className="field-input" name="placement"><option value="featured">Featured</option><option value="homepage">Homepage</option><option value="search_top">Top of search</option><option value="regional">Regional</option><option value="category">Category</option></select><select className="field-input" name="duration"><option value="3">3 days · TZS 5,000</option><option value="7">7 days · TZS 10,000</option><option value="30">30 days · TZS 30,000</option></select><button className="btn btn-success" disabled={busy}>Create and pay</button></form></section>
      <OperationList title="My featured campaigns" rows={boosts} />
      <OperationList title="Receipts" rows={receipts} />
    </>}
  </div>;
}

function OperationList({ title, rows, actions }: { title: string; rows: Row[]; actions?: (row: Row) => React.ReactNode }) {
  return <section className="surface-card p-6"><h2 className="font-heading text-2xl font-semibold">{title}</h2><div className="mt-4 grid gap-3">{rows.length === 0 ? <p className="text-muted">No records.</p> : rows.map((row) => <article className="rounded-xl border border-brand-border p-4" key={String(row.id)}><div className="flex flex-wrap items-start justify-between gap-3"><div><p className="font-semibold">{String(row.title ?? row.product_type ?? row.risk_type ?? row.payment_kind ?? row.id)}</p><p className="mt-1 text-xs text-muted">{String(row.status ?? row.payment_status ?? "recorded")} · {String(row.amount_tzs ?? row.requested_amount ?? "")} {row.created_at ? new Date(String(row.created_at)).toLocaleString() : ""}</p></div><div className="flex gap-2">{actions?.(row)}</div></div></article>)}</div></section>;
}
