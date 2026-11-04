"use client";
import { safeUserMessage } from "@/lib/user-message";
import { translateUiPrompt } from "@/lib/ui-translation";
import { UiInput, UiSelect, UiText } from "@/components/ui-text";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { getBrowserSupabase } from "@/lib/supabase-browser";

type Row = Record<string, unknown>;
const stages = ["submitted", "triage", "duplicate_review", "contacting_owner", "field_verification", "verified", "publication_review", "published", "ineligible", "closed"];
const rows = (value: unknown): Row[] => Array.isArray(value) ? value as Row[] : [];
const relation = (value: unknown): Row => (Array.isArray(value) ? value[0] : value) as Row ?? {};
const errorMessage = (error: unknown) => safeUserMessage(error);

export function InformationAdminWorkspace() {
  const db = useMemo(() => getBrowserSupabase(), []);
  const [leads, setLeads] = useState<Row[]>([]);
  const [agents, setAgents] = useState<Row[]>([]);
  const [listings, setListings] = useState<Row[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [stage, setStage] = useState("");
  const [page, setPage] = useState(0);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [more, setMore] = useState(false);
  const load = useCallback(async () => {
    setLoading(true);
    try {
      let query = db.from("rental_information_submissions")
        .select("id,reference,category,location_description,description,owner_name,owner_phone,owner_contact_authorized,information_source,status,eligibility_status,assigned_agent_id,linked_listing_id,next_follow_up_at,outcome,submitted_at,updated_at,information_follow_ups(id,summary,created_at),referral_agreements(id,reward_type,fixed_amount_tzs,percentage_rate,terms,terms_version,contributor_accepted_at,referral_rewards(id,status,reward_amount_tzs))")
        .order("submitted_at", { ascending: false }).range(page * 20, page * 20 + 19);
      if (stage) query = query.eq("status", stage);
      const result = await query;
      if (result.error) throw result.error;
      setLeads(rows(result.data)); setMore(rows(result.data).length === 20);
    } catch (error) { setMessage(errorMessage(error)); }
    finally { setLoading(false); }
  }, [db, page, stage]);
  useEffect(() => { const task = window.setTimeout(() => { void load(); }, 0); return () => window.clearTimeout(task); }, [load]);
  useEffect(() => {
    void Promise.all([
      db.rpc("get_assignable_verified_agents"),
      db.from("listings").select("id,title,agent_id").eq("status", "active").order("created_at", { ascending: false }).limit(200),
    ]).then(([agentResult, listingResult]) => {
      if (agentResult.error || listingResult.error) setMessage(errorMessage(agentResult.error ?? listingResult.error));
      else { setAgents(rows(agentResult.data)); setListings(rows(listingResult.data)); }
    });
  }, [db]);

  async function perform(action: () => PromiseLike<{ error: unknown }>) {
    setBusy(true); setMessage("");
    try { const result = await action(); if (result.error) throw result.error; await load(); setMessage("Saved."); }
    catch (error) { setMessage(errorMessage(error)); }
    finally { setBusy(false); }
  }
  const lead = leads.find((item) => item.id === selected);
  return <section className="grid gap-5">
    <div className="surface-card p-5"><h2 className="font-heading text-2xl font-semibold"><UiText text={"Information Administration"} /></h2>
      <p className="mt-2 text-sm text-muted"><UiText text={"Review private Toa Taarifa submissions, contact owners, assign verified agents and record referral terms. Finance approves and records payouts."} /></p>
      <div className="mt-4 flex flex-wrap gap-3"><UiSelect aria-label="Filter information stage" className="field-input max-w-xs" value={stage} onChange={(event) => { setStage(event.target.value); setPage(0); setSelected(null); }}><option value=""><UiText text={"All stages"} /></option>{stages.map((value) => <option key={value} value={value}><UiText text={value.replaceAll("_", " ")} /></option>)}</UiSelect><button className="btn btn-outline" onClick={() => void load()}><UiText text={"Refresh"} /></button></div>
      {message ? <p className="mt-4 text-sm" role="status"><UiText text={message} /></p> : null}
    </div>
    <div className="grid gap-5 xl:grid-cols-[minmax(240px,0.8fr)_minmax(0,1.4fr)]">
      <div className="grid content-start gap-3" aria-busy={loading}>{loading ? <p><UiText text={"Loading information…"} /></p> : leads.length === 0 ? <p><UiText text={"No submissions in this queue."} /></p> : leads.map((item) => <button key={String(item.id)} className={`surface-card p-5 text-left ${selected === item.id ? "ring-2 ring-brand-green" : ""}`} onClick={() => setSelected(String(item.id))}><strong>{String(item.reference)}</strong><p className="mt-2 text-sm">{String(item.location_description)}</p><p className="mt-2 text-xs font-semibold"><UiText text={String(item.status).replaceAll("_", " ")} /> · {String(item.eligibility_status)}</p></button>)}
        <div className="flex gap-3"><button className="btn btn-outline" disabled={!page || loading} onClick={() => { setPage(page - 1); setSelected(null); }}><UiText text={"Previous"} /></button><button className="btn btn-outline" disabled={!more || loading} onClick={() => { setPage(page + 1); setSelected(null); }}><UiText text={"Next"} /></button></div>
      </div>
      {lead ? <LeadReview key={`${lead.id}:${lead.updated_at}`} lead={lead} agents={agents} listings={listings} busy={busy} save={(values) => perform(() => db.rpc("manage_information_submission", { p_submission_id: lead.id, ...values } as never))} terms={(values) => perform(() => db.rpc("set_information_referral_terms", { p_submission_id: lead.id, ...values } as never))} /> : <div className="surface-card p-6 text-muted"><UiText text={"Select a submission to review its details and follow-up history."} /></div>}
    </div>
  </section>;
}

function LeadReview({ lead, agents, listings, busy, save, terms }: { lead: Row; agents: Row[]; listings: Row[]; busy: boolean; save: (values: Row) => Promise<void>; terms: (values: Row) => Promise<void> }) {
  const [status, setStatus] = useState(String(lead.status));
  const [agent, setAgent] = useState(String(lead.assigned_agent_id ?? ""));
  const agreement = relation(lead.referral_agreements);
  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); const form = new FormData(event.currentTarget);
    void save({ p_status: status, p_follow_up_note: form.get("note"), p_assigned_agent_id: agent || null,
      p_linked_listing_id: form.get("listing") || null, p_eligibility_status: lead.eligibility_status === "paid" ? null : form.get("eligibility"),
      p_next_follow_up_at: form.get("followUp") ? new Date(String(form.get("followUp"))).toISOString() : null, p_outcome: form.get("outcome") || null });
  }
  return <div className="grid gap-5"><section className="surface-card p-5">
    <h3 className="text-xl font-semibold">{String(lead.reference)}</h3><p className="mt-3 whitespace-pre-wrap">{String(lead.description)}</p><p className="mt-2 text-sm text-muted">{String(lead.location_description)}<UiText text={" · Source: "} />{String(lead.information_source)}</p>
    {lead.owner_contact_authorized ? <div className="soft-panel mt-4 p-4"><strong><UiText text={"Private owner contact"} /></strong><p>{String(lead.owner_name ?? "Not provided")}</p>{lead.owner_phone ? <a href={`tel:${String(lead.owner_phone)}`}>{String(lead.owner_phone)}</a> : null}</div> : <p className="mt-4 text-sm text-muted"><UiText text={"No authorized owner contact was supplied."} /></p>}
    <form className="mt-5 grid gap-4" onSubmit={submit}>
      <label className="field-label"><UiText text={"Stage"} /><select className="field-input mt-2" value={status} onChange={(event) => setStatus(event.target.value)}>{stages.map((value) => <option key={value}>{value}</option>)}</select></label>
      <label className="field-label"><UiText text={"Responsible verified agent"} /><select className="field-input mt-2" value={agent} onChange={(event) => setAgent(event.target.value)}><option value=""><UiText text={"Unassigned"} /></option>{agents.map((item) => <option key={String(item.id)} value={String(item.id)}>{String(item.business_name || item.display_name)}</option>)}</select></label>
      <label className="field-label"><UiText text={"Published listing"} /><select className="field-input mt-2" name="listing" defaultValue={String(lead.linked_listing_id ?? "")}><option value=""><UiText text={"Not linked yet"} /></option>{listings.filter((item) => !agent || item.agent_id === agent).map((item) => <option key={String(item.id)} value={String(item.id)}>{String(item.title)}</option>)}</select></label>
      {lead.eligibility_status !== "paid" ? <label className="field-label"><UiText text={"Reward eligibility"} /><select className="field-input mt-2" name="eligibility" defaultValue={String(lead.eligibility_status)}>{["pending", "eligible", "ineligible"].map((value) => <option key={value}>{value}</option>)}</select></label> : <p><UiText text={"Reward payment recorded by Finance."} /></p>}
      <label className="field-label"><UiText text={"Next follow-up"} /><input className="field-input mt-2" type="datetime-local" name="followUp" /></label>
      {status === "closed" ? <label className="field-label"><UiText text={"Outcome"} /><select className="field-input mt-2" name="outcome" defaultValue={String(lead.outcome ?? "")} required><option value=""><UiText text={"Choose outcome"} /></option>{["rented", "sold", "owner_declined", "duplicate", "not_available", "invalid", "cancelled"].map((value) => <option key={value}>{value}</option>)}</select></label> : null}
      <label className="field-label"><UiText text={"Internal follow-up note"} /><textarea name="note" className="field-input mt-2" required minLength={3} /></label>
      <button className="btn btn-success" disabled={busy}><UiText text={busy ? "Saving…" : "Save follow-up"} /></button>
    </form>
  </section>
  <section className="surface-card p-5"><h3 className="text-xl font-semibold"><UiText text={"Contributor reward terms"} /></h3><p className="mt-2 text-sm text-muted"><UiText text={"The contributor must accept the terms. A reward is calculated after a completed booking and a verified service fee; deposits are excluded."} /></p>
    {agreement.contributor_accepted_at ? <div className="mt-4"><p className="whitespace-pre-wrap">{String(agreement.terms)}</p><p className="mt-2 font-semibold"><UiText text={"Accepted · "} /><UiText text={agreement.reward_type === "fixed" ? `${agreement.fixed_amount_tzs} TZS` : `${agreement.percentage_rate}% of collected service fee`} /></p>{rows(agreement.referral_rewards).map((reward) => <p key={String(reward.id)} className="mt-2">{String(reward.reward_amount_tzs)} TZS · <UiText text={String(reward.status)} /></p>)}</div> : <form className="mt-4 grid gap-3" onSubmit={(event) => { event.preventDefault(); const form = new FormData(event.currentTarget); void terms({ p_reward_type: form.get("type"), p_amount: Number(form.get("amount")), p_terms: form.get("terms") }); }}>
      <label className="field-label"><UiText text={"Reward type"} /><select name="type" className="field-input mt-2" defaultValue={String(agreement.reward_type ?? "fixed")}><option value="fixed"><UiText text={"Fixed amount (TZS)"} /></option><option value="percentage"><UiText text={"Percentage of verified service fee"} /></option></select></label>
      <label className="field-label"><UiText text={"Amount or percentage"} /><input className="field-input mt-2" name="amount" type="number" min="0.01" step="0.01" defaultValue={String(agreement.fixed_amount_tzs ?? agreement.percentage_rate ?? "")} required /></label>
      <label className="field-label"><UiText text={"Terms for the contributor"} /><textarea className="field-input mt-2" name="terms" minLength={10} defaultValue={String(agreement.terms ?? "")} required /></label><button className="btn btn-success" disabled={busy}><UiText text={"Send terms for acceptance"} /></button>
    </form>}
  </section>
  <section className="surface-card p-5"><h3 className="font-semibold"><UiText text={"Internal follow-up history"} /></h3>{rows(lead.information_follow_ups).sort((a, b) => String(b.created_at).localeCompare(String(a.created_at))).map((item) => <p key={String(item.id)} className="mt-3 whitespace-pre-wrap text-sm">{String(item.summary)}<span className="mt-1 block text-xs text-muted">{new Date(String(item.created_at)).toLocaleString()}</span></p>)}</section>
  </div>;
}

export function ReferralFinancePanel() {
  const db = useMemo(() => getBrowserSupabase(), []);
  const [rewards, setRewards] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const load = useCallback(async () => { setLoading(true); try { const result = await db.rpc("get_information_finance_rewards"); if (result.error) throw result.error; setRewards(rows(result.data)); } catch (error) { setMessage(errorMessage(error)); } finally { setLoading(false); } }, [db]);
  useEffect(() => { const task = window.setTimeout(() => { void load(); }, 0); return () => window.clearTimeout(task); }, [load]);
  async function action(reward: Row, status: string) {
    const note = window.prompt(translateUiPrompt("Explain this finance decision:")); if (!note) return;
    setBusy(true); try { const result = await db.rpc("review_information_referral_reward", { p_reward_id: reward.id, p_action: status, p_note: note } as never); if (result.error) throw result.error; await load(); } catch (error) { setMessage(errorMessage(error)); } finally { setBusy(false); }
  }
  async function record(event: FormEvent<HTMLFormElement>, reward: Row) {
    event.preventDefault(); const form = new FormData(event.currentTarget); setBusy(true);
    try { const result = await db.rpc("record_referral_payout", { p_reward_id: reward.id, p_transaction_reference: form.get("reference"), p_payment_method: form.get("method"), p_notes: form.get("note") || null } as never); if (result.error) throw result.error; await load(); setMessage("Completed payout recorded. No transfer was initiated by this form."); }
    catch (error) { setMessage(errorMessage(error)); } finally { setBusy(false); }
  }
  return <section className="surface-card p-5"><div className="flex flex-wrap justify-between gap-3"><h2 className="text-2xl font-semibold"><UiText text={"Contributor reward payments"} /></h2><button className="btn btn-outline" onClick={() => void load()}><UiText text={"Refresh"} /></button></div>
    <p className="mt-2 text-sm text-muted"><UiText text={"Review verified reward obligations, then record payments completed through your payment provider. This form does not send money."} /></p>
    {message ? <p className="mt-4 text-sm" role="status"><UiText text={message} /></p> : null}
    {loading ? <p className="mt-4"><UiText text={"Loading rewards…"} /></p> : rewards.length === 0 ? <p className="mt-4 text-muted"><UiText text={"No calculated rewards yet."} /></p> : rewards.map((reward) => <article key={String(reward.id)} className="soft-panel mt-4 p-4"><strong>{String(reward.submission_reference)} · {String(reward.reward_amount_tzs)} TZS</strong><p className="mt-2">{String(reward.contributor_name)} · {String(reward.contributor_phone || reward.contributor_email)}</p><p className="mt-2 text-sm"><UiText text={"Verified service fee: "} />{String(reward.eligible_fee_collected_tzs)} TZS · <UiText text={String(reward.status)} /></p>
      {!["paid", "rejected"].includes(String(reward.status)) ? <div className="mt-3 flex flex-wrap gap-2">{["approved", "on_hold", "rejected"].map((status) => <button key={status} className="btn btn-outline" disabled={busy} onClick={() => void action(reward, status)}><UiText text={status.replaceAll("_", " ")} /></button>)}</div> : null}
      {reward.status === "approved" ? <form className="mt-4 grid gap-3 sm:grid-cols-2" onSubmit={(event) => void record(event, reward)}><label className="field-label"><UiText text={"Completed transaction reference"} /><input name="reference" className="field-input mt-2" minLength={3} required /></label><label className="field-label"><UiText text={"Payment method"} /><UiInput name="method" className="field-input mt-2" placeholder="M-Pesa, bank transfer…" required /></label><label className="field-label"><UiText text={"Payment note"} /><input name="note" className="field-input mt-2" /></label><button className="btn btn-success self-end" disabled={busy}><UiText text={"Record completed payout"} /></button></form> : null}
      {reward.payout ? <p className="mt-3 text-sm"><UiText text={"Payment reference: "} />{String(relation(reward.payout).transaction_reference)}</p> : null}
    </article>)}
  </section>;
}
