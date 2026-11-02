"use client";
import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { getBrowserSupabase } from "@/lib/supabase-browser";
import { UiText } from "@/components/ui-text";

type PublicationMode = { payment_required: boolean; amount_tzs: number; admin_approval_required: boolean };
async function currentMode(db: ReturnType<typeof getBrowserSupabase>) {
  const result = await db.rpc("get_agent_listing_publication_mode").abortSignal(AbortSignal.timeout(10000)) as unknown as { data: PublicationMode[] | null; error: unknown };
  if (result.error || !result.data?.[0] || typeof result.data[0].payment_required !== "boolean") throw result.error ?? new Error("Settings unavailable");
  return result.data[0];
}

/** Complete the same fee/approval workflow as Manage mobile, after media upload. */
export function ListingPublication({ listingId }: { listingId: string }) {
  const db = useMemo(() => getBrowserSupabase(), []);
  const [busy, setBusy] = useState(false);
  const [paymentId, setPaymentId] = useState("");
  const [message, setMessage] = useState("");
  const [mode, setMode] = useState<PublicationMode | null>(null);
  const [complete, setComplete] = useState(false);
  useEffect(() => {
    let active = true;
    void currentMode(db).then((value) => { if (active) setMode(value); }).catch(() => { /* Submission retries the settings lookup and fails closed. */ });
    return () => { active = false; };
  }, [db]);
  async function finish() {
    const listing = await db.from("listings").select("status").eq("id", listingId).abortSignal(AbortSignal.timeout(10000)).single();
    if (listing.error) throw listing.error;
    const published = (listing.data as { status: string }).status === "active";
    const latest = await currentMode(db); setMode(latest);
    setComplete(published || latest.admin_approval_required);
    setMessage(published ? "Listing uploaded and published." : latest.admin_approval_required ? "Listing uploaded. Awaiting approval." : "Listing saved. Publication is still pending. Please submit again to check the current requirements.");
  }
  async function submit() {
    if (busy) return;
    setBusy(true); setMessage("");
    try {
      const listing = await db.from("listings").select("status,removed_reason,removed_from_market_at").eq("id", listingId).abortSignal(AbortSignal.timeout(10000)).single();
      if (listing.error) throw listing.error;
      const row = listing.data as { status: string; removed_reason: string | null; removed_from_market_at: string | null };
      if (row.status === "active") { await finish(); return; }
      if (!["draft", "inactive"].includes(row.status) || row.removed_reason || row.removed_from_market_at) throw new Error("Listing unavailable");
      // The release function accepts inactive completed listings; media is already saved.
      if (row.status === "draft") {
        const staged = await db.from("listings").update({ status: "inactive" } as never).eq("id", listingId).eq("status", "draft").abortSignal(AbortSignal.timeout(15000));
        if (staged.error) throw staged.error;
      }
      const latest = await currentMode(db); setMode(latest);
      let currentPayment = latest.payment_required ? paymentId : "";
      if (!latest.payment_required) setPaymentId("");
      if (latest.payment_required && !currentPayment) {
        const existing = await db.from("agent_listing_payments").select("id,payment_status").eq("listing_id", listingId).abortSignal(AbortSignal.timeout(10000)).maybeSingle();
        if (existing.error) throw existing.error;
        const previous = existing.data as { id: string; payment_status: string } | null;
        if (previous && !["failed", "expired", "cancelled"].includes(previous.payment_status)) currentPayment = previous.id;
      }
      if (currentPayment) {
        setPaymentId(currentPayment);
        const checked = await db.functions.invoke("check-agent-listing-payment", { body: { payment_id: currentPayment }, signal: AbortSignal.timeout(25000) });
        if (checked.error || checked.data?.error) throw checked.error ?? new Error("Payment check failed");
        if (checked.data?.paymentRequired === false || checked.data?.paymentStatus === "paid") await finish();
        else if (["failed", "expired", "cancelled"].includes(checked.data?.paymentStatus)) { setPaymentId(""); setMessage("Payment was not completed. You can try again."); }
        else setMessage("Confirm the payment request on your agent phone, then check payment.");
        return;
      }
      const result = await db.functions.invoke("create-agent-listing-payment", { body: { listing_id: listingId }, signal: AbortSignal.timeout(30000) });
      if (result.error || result.data?.error || !result.data?.success) throw result.error ?? new Error("Submission failed");
      if (result.data.paymentRequired === false || result.data.paymentStatus === "paid") await finish();
      else {
        if (!result.data.paymentId) throw new Error("No payment reference");
        setPaymentId(String(result.data.paymentId));
        setMessage("Confirm the payment request on your agent phone, then check payment.");
      }
    } catch { setMessage("We could not confirm publication. Your uploaded asset is saved. Please try again or check My listings."); }
    finally { setBusy(false); }
  }
  return <section className="soft-panel grid gap-3 p-4">
    <h3 className="font-semibold"><UiText text="Submit listing" /></h3>
    <p><UiText text="Submit your uploaded asset for publication. Your existing plan fees and approval rules apply." /></p>
    {mode && <p role="status">{mode.payment_required ? <><UiText text="Publication fee (TZS)" />: {mode.amount_tzs.toLocaleString()}</> : <UiText text="Free publication" />}{mode.admin_approval_required && <> · <UiText text="Administrator approval is required." /></>}</p>}
    {message && <p role="status" aria-live="polite"><UiText text={message} /></p>}
    {!complete && <button type="button" className="btn btn-success" disabled={busy} onClick={() => void submit()}><UiText text={busy ? "Submitting..." : paymentId ? "Check payment" : "Submit listing"} /></button>}
    <Link className="btn btn-outline" href="/manage/listings?workspace=agent"><UiText text="My listings" /></Link>
  </section>;
}
