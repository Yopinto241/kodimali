"use client";
import { safeUserMessage } from "@/lib/user-message";
import { UiInput, UiText, UiTextarea } from "@/components/ui-text";

import Link from "next/link";
import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { User } from "@supabase/supabase-js";

import { getBrowserSupabase } from "@/lib/supabase-browser";
import { useLanguage } from "@/components/language-provider";

type Submission = {
  id: string;
  reference: string;
  category: string;
  location_description: string;
  description: string;
  approximate_rent: number | null;
  available_from: string | null;
  status: string;
  eligibility_status: string;
  submitted_at: string;
  referral_agreements: Record<string, unknown>[] | Record<string, unknown> | null;
};

const categories = [
  ["house", "Nyumba"],
  ["apartment", "Apartment"],
  ["office", "Ofisi"],
  ["car", "Gari"],
  ["motorcycle", "Pikipiki"],
  ["meeting_hall", "Ukumbi wa mikutano"],
  ["ceremony_hall", "Ukumbi wa sherehe"],
  ["equipment", "Vifaa"],
  ["farms", "Shamba"],
  ["other_asset", "Mali nyingine"],
] as const;

export function CustomerReferralPortal({ historyOnly = false }: { historyOnly?: boolean }) {
  const { language } = useLanguage();
  const sw = language === "sw";
  const supabase = useMemo(() => getBrowserSupabase(), []);
  const activeUser = useRef<string | null>(null);
  const latestRequest = useRef(0);
  const [authLoading, setAuthLoading] = useState(true);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [historyError, setHistoryError] = useState<string | null>(null);
  const [page, setPage] = useState(0);
  const [hasMore, setHasMore] = useState(false);
  const [pricePeriod, setPricePeriod] = useState("month");
  const [user, setUser] = useState<User | null>(null);
  const [submissions, setSubmissions] = useState<Submission[]>([]);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [category, setCategory] = useState("house");
  const [source, setSource] = useState("moving_out");
  const [location, setLocation] = useState("");
  const [description, setDescription] = useState("");
  const [rent, setRent] = useState("");
  const [availableFrom, setAvailableFrom] = useState("");
  const [ownerName, setOwnerName] = useState("");
  const [ownerPhone, setOwnerPhone] = useState("");
  const [ownerAuthorized, setOwnerAuthorized] = useState(false);
  const [submitted, setSubmitted] = useState(false);

  const loadSubmissions = useCallback(async (uid = activeUser.current, currentPage = page) => {
    if (!uid) return;
    const request = ++latestRequest.current;
    setHistoryLoading(true); setHistoryError(null);
    try {
      const { data, error } = await supabase.from("rental_information_submissions")
        .select("id,reference,category,location_description,description,approximate_rent,available_from,status,eligibility_status,submitted_at,referral_agreements(id,reward_type,fixed_amount_tzs,percentage_rate,terms,terms_version,contributor_accepted_at,referral_rewards(id,reward_amount_tzs,status,referral_payouts(transaction_reference,payment_method,paid_at)))")
        .eq("contributor_id", uid).order("submitted_at", { ascending: false }).range(currentPage * 20, currentPage * 20 + 19);
      if (error) throw error;
      if (activeUser.current === uid && latestRequest.current === request) { setSubmissions((data ?? []) as unknown as Submission[]); setHasMore((data ?? []).length === 20); }
    } catch (error) { if (activeUser.current === uid && latestRequest.current === request) setHistoryError(readError(error)); }
    finally { if (activeUser.current === uid && latestRequest.current === request) setHistoryLoading(false); }
  }, [page, supabase]);

  useEffect(() => {
    let mounted = true;
    const applyUser = (nextUser: User | null) => {
      if (!mounted) return;
      if (activeUser.current !== (nextUser?.id ?? null)) { latestRequest.current++; setPage(0); setSubmissions([]); }
      activeUser.current = nextUser?.id ?? null;
      setUser(nextUser); setAuthLoading(false);
    };
    void supabase.auth.getSession().then(({ data }) => applyUser(data.session?.user ?? null));
    const { data } = supabase.auth.onAuthStateChange((_event, session) => applyUser(session?.user ?? null));
    return () => { mounted = false; activeUser.current = null; data.subscription.unsubscribe(); };
  }, [supabase]);
  useEffect(() => { if (user) void loadSubmissions(user.id); }, [user, loadSubmissions]);

  async function acceptTerms(agreement: Record<string, unknown>) {
    setBusy(true); setMessage(null);
    try {
      const { error } = await supabase.rpc("accept_information_referral_terms", { p_agreement_id: agreement.id, p_terms_version: agreement.terms_version } as never);
      if (error) throw error;
      await loadSubmissions(); setMessage(sw ? "Umekubali masharti ya zawadi." : "Reward terms accepted.");
    } catch (error) { setMessage(readError(error)); } finally { setBusy(false); }
  }

  async function submitReferral(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setMessage(null);
    setSubmitted(false);
    try {
      const approximateRent = rent.trim() ? Number(rent) : null;
      if (approximateRent !== null && (!Number.isFinite(approximateRent) || approximateRent < 0)) {
        throw new Error("Weka kiasi sahihi cha kodi.");
      }
      if ((ownerName.trim() || ownerPhone.trim()) && !ownerAuthorized) {
        throw new Error("Thibitisha kuwa una ruhusa kabla ya kutuma mawasiliano ya mmiliki.");
      }
      const { error } = await supabase.rpc("submit_rental_information", {
        p_category: category,
        p_location_id: null,
        p_location_description: location.trim(),
        p_description: description.trim(),
        p_approximate_rent: approximateRent,
        p_price_period: approximateRent === null ? null : pricePeriod,
        p_available_from: availableFrom ? new Date(`${availableFrom}T00:00:00`).toISOString() : null,
        p_information_source: source,
        p_category_details: {
          contributor_is_moving_out: source === "moving_out",
          move_out_date: source === "moving_out" && availableFrom ? availableFrom : null,
        },
        p_photo_paths: [],
        p_photo_permission_confirmed: false,
        p_owner_name: ownerName.trim() || null,
        p_owner_phone: ownerPhone.trim() || null,
        p_owner_contact_authorized: ownerAuthorized,
      } as never);
      if (error) throw error;
      setLocation(""); setDescription(""); setRent(""); setAvailableFrom("");
      setOwnerName(""); setOwnerPhone(""); setOwnerAuthorized(false);
      setPage(0);
      await loadSubmissions(activeUser.current, 0);
      setSubmitted(true);
      setMessage("Taarifa yako imepokelewa kwa faragha. Tutaihakiki kabla ya kuchapishwa.");
    } catch (error) {
      setMessage(readError(error));
    } finally {
      setBusy(false);
    }
  }

  if (authLoading) return <p role="status"><UiText text={sw ? "Inapakia akaunti?" : "Loading your account?"} /></p>;

  if (!user) {
    return (
      <section className="referral-form-card p-6 sm:p-8">
        <h2 className="font-heading text-2xl font-semibold"><UiText text={sw ? "Ingia ili kutoa taarifa" : "Sign in to send information"} /></h2>
        <p className="section-copy mt-3"><UiText text={sw ? "Taarifa za mali na mawasiliano ya mmiliki huonekana na timu ya uhakiki pekee." : "Property details and the owner's contact information are visible only to the verification team."} /></p>
        <div className="mt-6 flex flex-wrap gap-3">
          <Link className="btn btn-success" href="/login?next=/toa-taarifa"><UiText text={sw ? "Ingia" : "Sign in"} /></Link>
          <Link className="btn btn-outline" href="/register?next=/toa-taarifa"><UiText text={sw ? "Jisajili" : "Register"} /></Link>
        </div>
      </section>
    );
  }

  return (
    <div className={historyOnly ? "grid gap-6" : "grid gap-6 lg:grid-cols-[1.1fr_0.9fr]"}>
      {!historyOnly ? <section className="referral-form-card p-6 sm:p-8">
        <p className="eyebrow"><UiText text={"Toa taarifa kwa faragha"} /></p>
        <h2 className="mt-2 font-heading text-2xl font-semibold"><UiText text={"Mali inayopatikana"} /></h2>
        <form className="mt-6 grid gap-4" onSubmit={submitReferral}>
          <label className="field-label"><UiText text={"Aina ya mali"} /><select className="field-input mt-2" value={category} onChange={(event) => setCategory(event.target.value)}>{categories.map(([value, label]) => <option value={value} key={value}><UiText text={label} /></option>)}</select></label>
          <label className="field-label"><UiText text={"Umeipataje taarifa hii?"} /><select className="field-input mt-2" value={source} onChange={(event) => setSource(event.target.value)}><option value="moving_out"><UiText text={"Ninahama kwenye nyumba/mali hii"} /></option><option value="owner"><UiText text={"Nimepewa taarifa na mmiliki"} /></option><option value="manager"><UiText text={"Nimepewa taarifa na msimamizi"} /></option><option value="community"><UiText text={"Nimeiona katika eneo langu"} /></option><option value="other"><UiText text={"Chanzo kingine"} /></option></select></label>
          <label className="field-label"><UiText text={"Eneo kamili kwa timu ya uhakiki"} /><UiInput className="field-input mt-2" value={location} onChange={(event) => setLocation(event.target.value)} placeholder="Mfano: Njiro, karibu na..." minLength={3} maxLength={500} required /></label>
          <label className="field-label"><UiText text={"Maelezo ya mali"} /><UiTextarea className="field-input mt-2 min-h-32" value={description} onChange={(event) => setDescription(event.target.value)} placeholder="Vyumba, hali ya mali, huduma na maelekezo muhimu" minLength={10} maxLength={4000} required /></label>
          <div className="grid gap-4 sm:grid-cols-2">
            <label className="field-label"><UiText text={"Bei/kodi ya makadirio (TZS)"} /><input className="field-input mt-2" type="number" min="0" step="1" value={rent} onChange={(event) => setRent(event.target.value)} /></label>
            <label className="field-label"><UiText text={source === "moving_out" ? "Tarehe unayohama" : "Inapatikana kuanzia"} /><input className="field-input mt-2" type="date" value={availableFrom} onChange={(event) => setAvailableFrom(event.target.value)} /></label>
          </div>
          <label className="field-label"><UiText text={"Kipindi cha bei"} /><select className="field-input mt-2" value={pricePeriod} onChange={(event) => setPricePeriod(event.target.value)}>{[["hour", "Kwa saa"], ["day", "Kwa siku"], ["week", "Kwa wiki"], ["month", "Kwa mwezi"], ["year", "Kwa mwaka"]].map(([value, label]) => <option key={value} value={value}><UiText text={label} /></option>)}</select></label>
          <div className="soft-panel grid gap-4 p-4">
            <div><h3 className="font-semibold"><UiText text={"Mawasiliano ya mmiliki (si lazima)"} /></h3><p className="mt-1 text-sm text-muted"><UiText text={"Yataonekana kwa Information Admin pekee, si kwa umma."} /></p></div>
            <label className="field-label"><UiText text={"Jina la mmiliki/msimamizi"} /><input className="field-input mt-2" value={ownerName} onChange={(event) => setOwnerName(event.target.value)} /></label>
            <label className="field-label"><UiText text={"Simu ya mmiliki/msimamizi"} /><input className="field-input mt-2" type="tel" value={ownerPhone} onChange={(event) => setOwnerPhone(event.target.value)} /></label>
            <label className="flex items-start gap-3 text-sm font-semibold"><input className="mt-1 h-4 w-4" type="checkbox" checked={ownerAuthorized} onChange={(event) => setOwnerAuthorized(event.target.checked)} /><span><UiText text={"Nina ruhusa ya kushiriki mawasiliano haya na KODIMALI kwa madhumuni ya uhakiki."} /></span></label>
          </div>
          <p className="text-sm text-muted"><UiText text={"Kutuma taarifa hakuchapishi listing moja kwa moja wala hakuhakikishi zawadi. Timu itathibitisha mali, ruhusa ya mmiliki na masharti ya referral."} /></p>
          <button className="btn btn-success" disabled={busy}><UiText text={busy ? "Inatuma..." : "Tuma taarifa kwa usalama"} /></button>
        </form>
        {message ? <div className="mt-4 rounded-2xl bg-brand-info-soft p-4 text-sm text-brand-navy" role="status"><p><UiText text={message} /></p>{submitted ? <div className="mt-4 flex flex-wrap gap-3"><a className="btn btn-success" href="#taarifa-zangu"><UiText text={"Angalia Taarifa Zangu"} /></a><Link className="btn btn-outline" href="/account"><UiText text={"Rudi Akaunti Yangu"} /></Link></div> : null}</div> : null}
      </section> : null}

      <section id="taarifa-zangu" className="referral-history-card scroll-mt-40 p-6 sm:p-8">
        <p className="eyebrow"><UiText text={"Taarifa Zangu"} /></p>
        <h2 className="mt-2 font-heading text-2xl font-semibold"><UiText text={"Ufuatiliaji na zawadi"} /></h2>
        <div className="mt-4 flex flex-wrap gap-3"><button className="btn btn-outline" disabled={historyLoading} onClick={() => void loadSubmissions()}><UiText text={sw ? "Pakia upya" : "Refresh"} /></button>{historyOnly ? <Link className="btn btn-success" href="/toa-taarifa#referral-form"><UiText text={"Toa Taarifa"} /></Link> : <Link className="btn btn-outline" href="/account?section=information"><UiText text={"Akaunti Yangu"} /></Link>}</div>
        {historyOnly && message ? <p className="mt-4 text-sm" role="status"><UiText text={message} /></p> : null}
        <div className="mt-6 grid gap-3" aria-busy={historyLoading}>
          {historyError ? <p role="alert">{historyError}</p> : historyLoading ? <p><UiText text={sw ? "Inapakia taarifa zako?" : "Loading your submissions?"} /></p> : submissions.length === 0 ? <p className="section-copy"><UiText text={"Bado hujatuma taarifa yoyote."} /></p> : submissions.map((submission) => (
            <article className="soft-panel p-4" key={submission.id}>
              <div className="flex flex-wrap items-start justify-between gap-3"><div><p className="font-semibold">{submission.reference} · {categoryLabel(submission.category)}</p><p className="mt-1 text-sm text-muted">{submission.location_description}</p></div><span className="rounded-full bg-brand-green-soft px-3 py-1 text-xs font-semibold text-brand-navy">{statusLabel(submission.status)}</span></div>
              <p className="mt-3 line-clamp-2 text-sm">{submission.description}</p>
              <p className="mt-3 text-sm font-semibold"><UiText text={"Zawadi: "} />{eligibilityLabel(submission.eligibility_status)}</p>
              <ReferralTerms agreement={Array.isArray(submission.referral_agreements) ? submission.referral_agreements[0] : submission.referral_agreements} busy={busy} accept={acceptTerms} sw={sw} />
            </article>
          ))}
        </div>
        <div className="mt-4 flex gap-3"><button className="btn btn-outline" disabled={page === 0 || historyLoading} onClick={() => setPage(page - 1)}><UiText text={"Previous"} /></button><button className="btn btn-outline" disabled={!hasMore || historyLoading} onClick={() => setPage(page + 1)}><UiText text={"Next"} /></button></div>
      </section>
    </div>
  );
}

function categoryLabel(value: string) { return categories.find(([key]) => key === value)?.[1] ?? value.replaceAll("_", " "); }
function statusLabel(value: string) { return ({ submitted: "Imepokelewa", triage: "Inakaguliwa", duplicate_review: "Ukaguzi wa nakala", contacting_owner: "Tunawasiliana na mmiliki", field_verification: "Uhakiki wa eneo", verified: "Imethibitishwa", publication_review: "Inasubiri kuchapishwa", published: "Imechapishwa", ineligible: "Haijakidhi vigezo", closed: "Imefungwa" } as Record<string, string>)[value] ?? value; }
function eligibilityLabel(value: string) { return ({ pending: "Inasubiri uhakiki", eligible: "Inastahili", ineligible: "Haistahili", paid: "Imelipwa" } as Record<string, string>)[value] ?? value; }
function readError(error: unknown) { return safeUserMessage(error); }

function ReferralTerms({ agreement, busy, accept, sw }: { agreement?: Record<string, unknown> | null; busy: boolean; accept: (agreement: Record<string, unknown>) => Promise<void>; sw: boolean }) {
  if (!agreement) return <p className="mt-3 text-sm text-muted"><UiText text={sw ? "Masharti na kiasi cha zawadi vitaonekana baada ya uhakiki." : "Reward terms and amounts will appear after review."} /></p>;
  const rewards = Array.isArray(agreement.referral_rewards) ? agreement.referral_rewards as Record<string, unknown>[] : [];
  return <div className="mt-4 rounded-xl border border-brand-border p-4">
    <strong><UiText text={sw ? "Masharti ya zawadi" : "Reward terms"} /> ? <UiText text={agreement.reward_type === "fixed" ? `${agreement.fixed_amount_tzs} TZS` : `${agreement.percentage_rate}%`} /></strong>
    <p className="mt-2 whitespace-pre-wrap text-sm">{String(agreement.terms)}</p>
    <p className="mt-2 text-xs text-muted"><UiText text={sw ? "Asilimia huhesabiwa kwenye ada ya huduma iliyothibitishwa, si amana au bei yote ya booking. Zawadi inahitaji booking iliyokamilika na idhini ya Finance." : "Percentages apply to verified service fees, excluding deposits and the full booking price. Rewards require a completed booking and Finance approval."} /></p>
    {agreement.contributor_accepted_at ? <p className="mt-3 text-sm font-semibold"><UiText text={sw ? "Umekubali masharti haya" : "You accepted these terms"} /></p> : <button className="btn btn-success mt-3" disabled={busy} onClick={() => void accept(agreement)}><UiText text={sw ? "Nimesoma na kukubali masharti" : "I have read and accept these terms"} /></button>}
    {rewards.map((reward) => { const payout = Array.isArray(reward.referral_payouts) ? reward.referral_payouts[0] : reward.referral_payouts; return <div key={String(reward.id)} className="mt-3 border-t border-brand-border pt-3"><p className="font-semibold">{String(reward.reward_amount_tzs)} TZS ? <UiText text={String(reward.status).replaceAll("_", " ")} /></p>{payout ? <p className="mt-1 text-sm"><UiText text={sw ? "Malipo" : "Payment"} />: {String(payout.transaction_reference)} ? {String(payout.payment_method)}</p> : null}</div>; })}
  </div>;
}
