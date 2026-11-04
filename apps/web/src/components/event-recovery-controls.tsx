"use client";
import { safeUserMessage } from "@/lib/user-message";
import { UiText } from "@/components/ui-text";

import { useCallback, useEffect, useState } from "react";
import { getBrowserSupabase } from "@/lib/supabase-browser";
import { useLanguage } from "@/components/language-provider";

type Proposal = { id: string; reason: string; price_change_tzs: number; status: string; expires_at: string; equipment: { name: string } | null; service: { title: string } | null };

export function EventRecoveryControls({ planId, status, onChange }: { planId: string; status: string; onChange: () => Promise<void> }) {
  const supabase = getBrowserSupabase();
  const { language } = useLanguage();
  const sw = language === "sw";
  const [proposals, setProposals] = useState<Proposal[]>([]);
  const [cancellations, setCancellations] = useState<Array<{ id: string; status: string; reason: string; resolution: string | null; refundable_amount_tzs: number | null }>>([]);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const load = useCallback(async () => {
    const { data, error } = await supabase.from("event_substitution_proposals").select("id,reason,price_change_tzs,status,expires_at,equipment:event_equipment_items!proposed_equipment_id(name),service:event_service_offerings!proposed_offering_id(title)").eq("plan_id", planId).order("created_at", { ascending: false });
    if (error) throw error;
    setProposals((data ?? []) as unknown as Proposal[]);
    const reviews = await supabase.from("event_cancellations").select("id,status,reason,resolution,refundable_amount_tzs").eq("plan_id", planId).order("created_at", { ascending: false });
    if (reviews.error) throw reviews.error;
    setCancellations(reviews.data ?? []);
  }, [planId, supabase]);
  useEffect(() => { const task = window.setTimeout(() => { void load().catch((error) => setMessage(safeUserMessage(error))); }, 0); return () => window.clearTimeout(task); }, [load]);

  async function act(name: string, params: Record<string, unknown>) {
    setBusy(true); setMessage("");
    try {
      const { error } = await supabase.rpc(name, params as never);
      if (error) throw error;
      await Promise.all([load(), onChange()]);
      setMessage(sw ? "Mabadiliko yamehifadhiwa. Malipo au marejesho yanahitaji uhakiki." : "Saved. Any payment or refund requires review.");
    } catch (error) { setMessage(safeUserMessage(error)); }
    finally { setBusy(false); }
  }

  return <div className="mt-4 space-y-3">
    {proposals.map((proposal) => <div key={proposal.id} className="rounded-2xl border border-brand-border p-4">
      <p className="font-semibold"><UiText text={sw ? "Mbadala uliopendekezwa" : "Proposed replacement"} />: {proposal.equipment?.name ?? proposal.service?.title ?? "—"}</p>
      <p className="mt-2 text-sm">{proposal.reason}</p>
      <p className="mt-2 text-sm font-semibold"><UiText text={sw ? "Tofauti ya bei" : "Price change"} />: TZS {Number(proposal.price_change_tzs).toLocaleString()}</p>
      <p className="mt-1 text-sm text-muted"><UiText text={sw ? "Mtoa huduma lazima athibitishe, kisha utakagua quotation mpya kabla ya malipo." : "The replacement provider must confirm. You will review a revised quotation before any new payment."} /></p>
      {proposal.status === "proposed" && new Date(proposal.expires_at) > new Date() ? <div className="mt-3 flex flex-wrap gap-2">
        <button className="btn btn-outline" disabled={busy} onClick={() => void act("respond_event_replacement", { p_proposal_id: proposal.id, p_accept: false })}><UiText text={sw ? "Kataa" : "Decline"} /></button>
        <button className="btn btn-success" disabled={busy} onClick={() => void act("respond_event_replacement", { p_proposal_id: proposal.id, p_accept: true })}><UiText text={sw ? "Kubali mbadala" : "Accept replacement"} /></button>
      </div> : <p className="mt-2 text-sm">{proposal.status === "proposed" ? (sw ? "Imeisha muda" : "Expired") : proposal.status}</p>}
    </div>)}
    {!["cancelled", "completed"].includes(status) ? <details className="rounded-2xl border border-brand-border p-4"><summary className="cursor-pointer text-sm font-semibold"><UiText text={sw ? "Ghairi tukio" : "Cancel event"} /></summary>
      <form className="mt-3 space-y-3" onSubmit={(event) => { event.preventDefault(); void act("cancel_customer_event", { p_plan_id: planId, p_reason: reason }); }}>
        <p className="text-sm text-muted"><UiText text={sw ? "Hii itaachia vifaa na muda. Kiasi chochote kilicholipwa kitakaguliwa kwa masharti ya cancellation." : "This releases stock and provider time. Any money already paid will be reviewed under the cancellation terms."} /></p>
        <label className="field-label block"><UiText text={sw ? "Sababu" : "Reason"} /><textarea className="field-input mt-1" value={reason} onChange={(event) => setReason(event.target.value)} required minLength={3} maxLength={2000} /></label>
        <button disabled={busy} className="btn btn-outline"><UiText text={sw ? "Thibitisha kughairi" : "Confirm cancellation"} /></button>
      </form>
    </details> : null}
    {cancellations.map((review) => <div key={review.id} className="rounded-2xl border border-brand-border p-4 text-sm"><p className="font-semibold"><UiText text={sw ? "Ukaguzi wa cancellation" : "Cancellation review"} />: <UiText text={review.status} /></p><p>{review.reason}</p>{review.resolution ? <p className="mt-2">{review.resolution} <UiText text={review.refundable_amount_tzs != null ? ` ? TZS ${Number(review.refundable_amount_tzs).toLocaleString()}` : ""} /></p> : <p><UiText text={sw ? "Inasubiri uhakiki wa masharti na malipo." : "Awaiting review of the terms and any payments."} /></p>}</div>)}
    {message ? <p role="status" className="text-sm"><UiText text={message} /></p> : null}
  </div>;
}
