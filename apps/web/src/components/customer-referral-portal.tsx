"use client";

import Link from "next/link";
import { FormEvent, useCallback, useEffect, useState } from "react";
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

export function CustomerReferralPortal() {
  const { language } = useLanguage();
  const sw = language === "sw";
  const supabase = getBrowserSupabase();
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

  const loadSubmissions = useCallback(async () => {
    const { data, error } = await supabase
      .from("rental_information_submissions")
      .select("id,reference,category,location_description,description,approximate_rent,available_from,status,eligibility_status,submitted_at")
      .order("submitted_at", { ascending: false });
    if (error) throw error;
    setSubmissions((data ?? []) as Submission[]);
  }, [supabase]);

  useEffect(() => {
    const applyUser = (nextUser: User | null) => {
      setUser(nextUser);
      if (nextUser) void loadSubmissions().catch((error) => setMessage(readError(error)));
      else setSubmissions([]);
    };
    void supabase.auth.getUser().then(({ data }) => applyUser(data.user));
    const { data } = supabase.auth.onAuthStateChange((_event, session) => applyUser(session?.user ?? null));
    return () => data.subscription.unsubscribe();
  }, [loadSubmissions, supabase]);

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
        p_price_period: approximateRent === null ? null : "month",
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
      await loadSubmissions();
      setSubmitted(true);
      setMessage("Taarifa yako imepokelewa kwa faragha. Tutaihakiki kabla ya kuchapishwa.");
    } catch (error) {
      setMessage(readError(error));
    } finally {
      setBusy(false);
    }
  }

  if (!user) {
    return (
      <section className="referral-form-card p-6 sm:p-8">
        <h2 className="font-heading text-2xl font-semibold">{sw ? "Ingia ili kutoa taarifa" : "Sign in to send information"}</h2>
        <p className="section-copy mt-3">{sw ? "Taarifa za mali na mawasiliano ya mmiliki huonekana na timu ya uhakiki pekee." : "Property details and the owner's contact information are visible only to the verification team."}</p>
        <div className="mt-6 flex flex-wrap gap-3">
          <Link className="btn btn-success" href="/login?next=/toa-taarifa">{sw ? "Ingia" : "Sign in"}</Link>
          <Link className="btn btn-outline" href="/register?next=/toa-taarifa">{sw ? "Jisajili" : "Register"}</Link>
        </div>
      </section>
    );
  }

  return (
    <div className="grid gap-6 lg:grid-cols-[1.1fr_0.9fr]">
      <section className="referral-form-card p-6 sm:p-8">
        <p className="eyebrow">Toa taarifa kwa faragha</p>
        <h2 className="mt-2 font-heading text-2xl font-semibold">Mali inayopatikana</h2>
        <form className="mt-6 grid gap-4" onSubmit={submitReferral}>
          <label className="field-label">Aina ya mali<select className="field-input mt-2" value={category} onChange={(event) => setCategory(event.target.value)}>{categories.map(([value, label]) => <option value={value} key={value}>{label}</option>)}</select></label>
          <label className="field-label">Umeipataje taarifa hii?<select className="field-input mt-2" value={source} onChange={(event) => setSource(event.target.value)}><option value="moving_out">Ninahama kwenye nyumba/mali hii</option><option value="owner">Nimepewa taarifa na mmiliki</option><option value="manager">Nimepewa taarifa na msimamizi</option><option value="community">Nimeiona katika eneo langu</option><option value="other">Chanzo kingine</option></select></label>
          <label className="field-label">Eneo kamili kwa timu ya uhakiki<input className="field-input mt-2" value={location} onChange={(event) => setLocation(event.target.value)} placeholder="Mfano: Njiro, karibu na..." minLength={3} maxLength={500} required /></label>
          <label className="field-label">Maelezo ya mali<textarea className="field-input mt-2 min-h-32" value={description} onChange={(event) => setDescription(event.target.value)} placeholder="Vyumba, hali ya mali, huduma na maelekezo muhimu" minLength={10} maxLength={4000} required /></label>
          <div className="grid gap-4 sm:grid-cols-2">
            <label className="field-label">Kodi ya makadirio kwa mwezi (TZS)<input className="field-input mt-2" type="number" min="0" step="1" value={rent} onChange={(event) => setRent(event.target.value)} /></label>
            <label className="field-label">{source === "moving_out" ? "Tarehe unayohama" : "Inapatikana kuanzia"}<input className="field-input mt-2" type="date" value={availableFrom} onChange={(event) => setAvailableFrom(event.target.value)} /></label>
          </div>
          <div className="soft-panel grid gap-4 p-4">
            <div><h3 className="font-semibold">Mawasiliano ya mmiliki (si lazima)</h3><p className="mt-1 text-sm text-muted">Yataonekana kwa Information Admin pekee, si kwa umma.</p></div>
            <label className="field-label">Jina la mmiliki/msimamizi<input className="field-input mt-2" value={ownerName} onChange={(event) => setOwnerName(event.target.value)} /></label>
            <label className="field-label">Simu ya mmiliki/msimamizi<input className="field-input mt-2" type="tel" value={ownerPhone} onChange={(event) => setOwnerPhone(event.target.value)} /></label>
            <label className="flex items-start gap-3 text-sm font-semibold"><input className="mt-1 h-4 w-4" type="checkbox" checked={ownerAuthorized} onChange={(event) => setOwnerAuthorized(event.target.checked)} /><span>Nina ruhusa ya kushiriki mawasiliano haya na KODIMALI kwa madhumuni ya uhakiki.</span></label>
          </div>
          <p className="text-sm text-muted">Kutuma taarifa hakuchapishi listing moja kwa moja wala hakuhakikishi zawadi. Timu itathibitisha mali, ruhusa ya mmiliki na masharti ya referral.</p>
          <button className="btn btn-success" disabled={busy}>{busy ? "Inatuma..." : "Tuma taarifa kwa usalama"}</button>
        </form>
        {message ? <div className="mt-4 rounded-2xl bg-brand-info-soft p-4 text-sm text-brand-navy" role="status"><p>{message}</p>{submitted ? <div className="mt-4 flex flex-wrap gap-3"><a className="btn btn-success" href="#taarifa-zangu">Angalia Taarifa Zangu</a><Link className="btn btn-outline" href="/account">Rudi Akaunti Yangu</Link></div> : null}</div> : null}
      </section>

      <section id="taarifa-zangu" className="referral-history-card scroll-mt-40 p-6 sm:p-8">
        <p className="eyebrow">Taarifa Zangu</p>
        <h2 className="mt-2 font-heading text-2xl font-semibold">Ufuatiliaji na zawadi</h2>
        <div className="mt-6 grid gap-3">
          {submissions.length === 0 ? <p className="section-copy">Bado hujatuma taarifa yoyote.</p> : submissions.map((submission) => (
            <article className="soft-panel p-4" key={submission.id}>
              <div className="flex flex-wrap items-start justify-between gap-3"><div><p className="font-semibold">{submission.reference} · {categoryLabel(submission.category)}</p><p className="mt-1 text-sm text-muted">{submission.location_description}</p></div><span className="rounded-full bg-brand-green-soft px-3 py-1 text-xs font-semibold text-brand-navy">{statusLabel(submission.status)}</span></div>
              <p className="mt-3 line-clamp-2 text-sm">{submission.description}</p>
              <p className="mt-3 text-sm font-semibold">Zawadi: {eligibilityLabel(submission.eligibility_status)}</p>
            </article>
          ))}
        </div>
      </section>
    </div>
  );
}

function categoryLabel(value: string) { return categories.find(([key]) => key === value)?.[1] ?? value.replaceAll("_", " "); }
function statusLabel(value: string) { return ({ submitted: "Imepokelewa", triage: "Inakaguliwa", duplicate_review: "Ukaguzi wa nakala", contacting_owner: "Tunawasiliana na mmiliki", field_verification: "Uhakiki wa eneo", verified: "Imethibitishwa", publication_review: "Inasubiri kuchapishwa", published: "Imechapishwa", ineligible: "Haijakidhi vigezo", closed: "Imefungwa" } as Record<string, string>)[value] ?? value; }
function eligibilityLabel(value: string) { return ({ pending: "Inasubiri uhakiki", eligible: "Inastahili", ineligible: "Haistahili", paid: "Imelipwa" } as Record<string, string>)[value] ?? value; }
function readError(error: unknown) { return error instanceof Error ? error.message : "Ombi halikuweza kukamilika."; }
