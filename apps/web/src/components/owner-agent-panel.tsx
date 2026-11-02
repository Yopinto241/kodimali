"use client";
import { translateUiPrompt } from "@/lib/ui-translation";
import { UiInput, UiSelect, UiText } from "@/components/ui-text";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { getBrowserSupabase } from "@/lib/supabase-browser";
type Row = Record<string, unknown>;
const rows = (value: unknown): Row[] => Array.isArray(value) ? value as Row[] : [];
const errorText = (error: unknown) => String((error as Row)?.message ?? "Could not complete this request.");

export function OwnerAgentPanel({ assets }: { assets: Row[] }) {
  const db = useMemo(() => getBrowserSupabase(), []);
  const [agents, setAgents] = useState<Row[]>([]);
  const [delegations, setDelegations] = useState<Row[]>([]);
  const [recommendations, setRecommendations] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const load = useCallback(async () => {
    setLoading(true);
    try {
      const result = await Promise.all([db.rpc("get_assignable_verified_agents"), db.from("asset_agent_delegations").select("id,asset_id,agent_id,status,scopes").order("created_at", { ascending: false }), db.from("owner_agent_recommendations").select("id,suggested_name,suggested_phone,status,review_notes").order("created_at", { ascending: false })]);
      const error = result.find((item) => item.error)?.error; if (error) throw error;
      setAgents(rows(result[0].data)); setDelegations(rows(result[1].data)); setRecommendations(rows(result[2].data));
    } catch (error) { setMessage(errorText(error)); } finally { setLoading(false); }
  }, [db]);
  useEffect(() => { const task = window.setTimeout(() => { void load(); }, 0); return () => window.clearTimeout(task); }, [load]);
  async function perform(request: PromiseLike<{ error: unknown }>) {
    setBusy(true); setMessage("");
    try { const result = await request; if (result.error) throw result.error; await load(); setMessage("Saved."); }
    catch (error) { setMessage(errorText(error)); } finally { setBusy(false); }
  }
  function grant(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); const form = new FormData(event.currentTarget);
    void perform(db.rpc("grant_asset_agent_delegation", { p_asset_id: form.get("asset"), p_agent_id: form.get("agent") } as never));
  }
  return <div className="grid gap-5" aria-busy={loading}>
    <section className="surface-card p-6"><h2 className="text-2xl font-semibold"><UiText text={"My agents"} /></h2><p className="mt-2 text-sm text-muted"><UiText text={"Choose a verified agent for an asset you control. You can revoke their authority. Recommending someone does not grant access."} /></p>
      {message ? <p role="status" className="mt-4"><UiText text={message} /></p> : null}<button className="btn btn-outline mt-4" onClick={() => void load()}><UiText text={"Refresh"} /></button>
      {loading ? <p className="mt-4"><UiText text={"Loading agents…"} /></p> : <form className="mt-5 grid gap-4" onSubmit={grant}>
        <label className="field-label"><UiText text={"Verified asset"} /><select name="asset" className="field-input mt-2" required><option value=""><UiText text={"Choose asset"} /></option>{assets.filter((item) => item.status === "verified").map((item) => <option key={String(item.id)} value={String(item.asset_id)}>{String((item.rental_assets as Row)?.display_name ?? item.asset_id)}</option>)}</select></label>
        <label className="field-label"><UiText text={"Verified agent"} /><select name="agent" className="field-input mt-2" required><option value=""><UiText text={"Choose agent"} /></option>{agents.map((agent) => <option key={String(agent.id)} value={String(agent.id)}>{String(agent.business_name || agent.display_name)} · {String(agent.public_location_label ?? "")}</option>)}</select></label>
        <p className="text-sm text-muted"><UiText text={"Authority covers bookings, availability, fulfillment and customer communication for the selected asset."} /></p><button className="btn btn-success" disabled={busy}><UiText text={"Authorize selected agent"} /></button>
      </form>}
      {delegations.map((item) => <article className="soft-panel mt-4 flex flex-wrap items-center justify-between gap-3 p-4" key={String(item.id)}><div><strong>{String(agents.find((agent) => agent.id === item.agent_id)?.business_name ?? item.agent_id)}</strong><p className="text-sm"><UiText text={String(item.status)} /> · {String(item.asset_id)}</p></div>{item.status === "active" ? <button className="btn btn-outline" disabled={busy} onClick={() => { const reason = window.prompt(translateUiPrompt("Reason for revoking access:")); if (reason?.trim()) void perform(db.rpc("revoke_asset_agent_delegation", { p_delegation_id: item.id, p_reason: reason } as never)); }}><UiText text={"Revoke access"} /></button> : null}</article>)}
    </section>
    <section className="surface-card p-6"><h2 className="text-2xl font-semibold"><UiText text={"Recommend your own agent"} /></h2><p className="mt-2 text-sm text-muted"><UiText text={"Recommend a person you trust, including someone who has not registered. Agent Manager reviews the recommendation and verifies registration. You authorize them separately after approval."} /></p>
      <form className="mt-5 grid gap-4" onSubmit={(event) => { event.preventDefault(); const form = new FormData(event.currentTarget); void perform(db.rpc("recommend_owner_agent", { p_name: form.get("name"), p_phone: form.get("phone"), p_notes: form.get("notes") || null } as never)); }}>
        <label className="field-label"><UiText text={"Agent name"} /><input name="name" className="field-input mt-2" minLength={2} maxLength={180} required /></label><label className="field-label"><UiText text={"Phone"} /><input name="phone" type="tel" className="field-input mt-2" minLength={8} maxLength={40} required /></label><label className="field-label"><UiText text={"Recommendation note"} /><textarea name="notes" className="field-input mt-2" /></label><button className="btn btn-success" disabled={busy}><UiText text={"Submit recommendation"} /></button>
      </form>
      {recommendations.map((item) => <article className="soft-panel mt-4 p-4" key={String(item.id)}><strong>{String(item.suggested_name)}</strong><p><UiText text={String(item.status)} /></p>{item.review_notes ? <p className="mt-2 text-sm">{String(item.review_notes)}</p> : null}</article>)}
    </section>
  </div>;
}

export function OwnerAgentRecommendations() {
  const db = useMemo(() => getBrowserSupabase(), []);
  const [items, setItems] = useState<Row[]>([]);
  const [agents, setAgents] = useState<Row[]>([]);
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const load = useCallback(async () => {
    const [recommendations, directory] = await Promise.all([db.from("owner_agent_recommendations").select("id,suggested_name,suggested_phone,notes,status,registered_agent_id").order("created_at", { ascending: false }).limit(100), db.rpc("get_assignable_verified_agents")]);
    if (recommendations.error || directory.error) setMessage(errorText(recommendations.error ?? directory.error));
    else { setItems(rows(recommendations.data)); setAgents(rows(directory.data)); }
  }, [db]);
  useEffect(() => { const task = window.setTimeout(() => { void load(); }, 0); return () => window.clearTimeout(task); }, [load]);
  async function review(event: FormEvent<HTMLFormElement>, item: Row) {
    event.preventDefault(); const form = new FormData(event.currentTarget); setBusy(true);
    try { const result = await db.rpc("review_owner_agent_recommendation", { p_id: item.id, p_status: form.get("status"), p_agent_id: form.get("agent") || null, p_notes: form.get("note") || null } as never); if (result.error) throw result.error; await load(); setMessage("Recommendation review saved. The owner grants asset authority separately."); }
    catch (error) { setMessage(errorText(error)); } finally { setBusy(false); }
  }
  return <section className="surface-card mb-5 p-5"><h2 className="text-2xl font-semibold"><UiText text={"Owner-recommended agents"} /></h2><p className="mt-2 text-sm text-muted"><UiText text={"Verify registration before accepting a recommendation. Acceptance does not activate an unverified agent or grant asset access."} /></p>{message ? <p role="status" className="mt-3"><UiText text={message} /></p> : null}{items.length === 0 ? <p className="mt-4"><UiText text={"No recommendations yet."} /></p> : items.map((item) => <form className="soft-panel mt-4 grid gap-3 p-4" key={String(item.id)} onSubmit={(event) => void review(event, item)}><strong>{String(item.suggested_name)} · {String(item.suggested_phone)}</strong><p>{String(item.notes ?? "")}</p><p className="text-sm"><UiText text={"Current status: "} /><UiText text={String(item.status)} /></p><UiSelect aria-label="Recommendation status" name="status" className="field-input" defaultValue={item.status === "submitted" ? "contacting" : String(item.status)}>{["contacting", "accepted", "rejected"].map((value) => <option key={value}>{value}</option>)}</UiSelect><UiSelect aria-label="Verified agent linked to recommendation" className="field-input" name="agent" defaultValue={String(item.registered_agent_id ?? "")}><option value=""><UiText text={"Not registered/verified yet"} /></option>{agents.map((agent) => <option key={String(agent.id)} value={String(agent.id)}>{String(agent.business_name || agent.display_name)}</option>)}</UiSelect><UiInput aria-label="Review note" className="field-input" name="note" placeholder="Review note for owner" /><button className="btn btn-success" disabled={busy}><UiText text={"Save recommendation review"} /></button></form>)}</section>;
}
