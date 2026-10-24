"use client";

import Link from "next/link";
import { FormEvent, useEffect, useState } from "react";
import { useLanguage } from "@/components/language-provider";
import { getBrowserSupabase } from "@/lib/supabase-browser";

type Row = Record<string, unknown>;

export function EventAdvisor({ eventTypes }: { eventTypes: Row[] }) {
  const { language } = useLanguage();
  const sw = language === "sw";
  const supabase = getBrowserSupabase();
  const [templates, setTemplates] = useState<Row[]>([]);
  const [recommendations, setRecommendations] = useState<Row[]>([]);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  useEffect(() => { void supabase.from("event_templates").select("id,slug,name_sw,name_en,description_sw,description_en,setting,event_type_id").eq("is_approved", true).order("name_en").then(({ data }) => setTemplates((data ?? []) as Row[])); }, [supabase]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setNotice(""); setRecommendations([]);
    const { data: auth } = await supabase.auth.getUser();
    if (!auth.user) { window.location.assign("/login?next=/events%23advisor"); return; }
    const form = new FormData(event.currentTarget);
    const template = templates.find((row) => row.id === form.get("template"));
    const eventTypeId = String(template?.event_type_id ?? eventTypes[0]?.id ?? "");
    if (!eventTypeId) { setBusy(false); setNotice(sw ? "Aina ya tukio haijapatikana." : "No event type is available."); return; }
    const start = new Date(String(form.get("date"))); const end = new Date(start.getTime() + 6 * 60 * 60 * 1000);
    const { data: planData, error: planError } = await supabase.rpc("create_event_plan", { p_event_type_id: eventTypeId, p_start_at: start.toISOString(), p_end_at: end.toISOString(), p_location_id: null, p_private_location_details: form.get("location"), p_attendance: Number(form.get("guests")), p_budget_tzs: Number(form.get("budget")) || null, p_title: sw ? "Mpango kutoka Event Advisor" : "Event Advisor plan" } as never);
    const plan = planData as unknown as Row | null;
    if (planError || !plan?.id) { setBusy(false); setNotice(planError?.message ?? "Plan could not be created."); return; }
    const { data, error } = await supabase.rpc("run_event_advisor", { p_plan_id: plan.id, p_template_id: form.get("template"), p_setting: form.get("setting"), p_venue_status: form.get("venueStatus"), p_accessibility: form.get("accessibility"), p_weather_contingency: form.get("weather") } as never);
    setBusy(false);
    if (error) { setNotice(error.message); return; }
    setRecommendations((data ?? []) as Row[]);
    setNotice(sw ? `Mpango umehifadhiwa: ${String(plan.reference)}` : `Plan saved: ${String(plan.reference)}`);
  }

  return <section id="advisor" className="surface-card p-6 sm:p-8"><div className="grid gap-8 lg:grid-cols-[.8fr_1.2fr]"><div><p className="eyebrow">Event Advisor</p><h2 className="mt-3 font-heading text-3xl font-semibold">{sw ? "Unahitaji msaada kupanga?" : "Need help planning?"}</h2><p className="mt-3 text-muted">{sw ? "Jibu maswali mafupi. Tutakupa checklist inayoweza kuelezeka bila kubuni bei au availability." : "Answer a few questions. We will create an explainable checklist without inventing prices or availability."}</p></div><form className="grid gap-4 sm:grid-cols-2" onSubmit={submit}><label className="field-label sm:col-span-2">{sw ? "Template ya tukio" : "Event template"}<select className="field-input mt-2" name="template" required><option value="">{sw ? "Chagua" : "Choose"}</option>{templates.map((row) => <option key={String(row.id)} value={String(row.id)}>{String(sw ? row.name_sw : row.name_en)}</option>)}</select></label><label className="field-label">{sw ? "Tarehe na muda" : "Date and time"}<input className="field-input mt-2" name="date" type="datetime-local" required /></label><label className="field-label">{sw ? "Wageni" : "Guests"}<input className="field-input mt-2" name="guests" type="number" min="1" required /></label><label className="field-label">{sw ? "Eneo" : "Location"}<input className="field-input mt-2" name="location" required /></label><label className="field-label">{sw ? "Bajeti (TZS)" : "Budget (TZS)"}<input className="field-input mt-2" name="budget" type="number" min="0" /></label><label className="field-label">{sw ? "Mpangilio" : "Setting"}<select className="field-input mt-2" name="setting"><option value="indoor">Indoor</option><option value="outdoor">Outdoor</option></select></label><label className="field-label">{sw ? "Hali ya venue" : "Venue status"}<select className="field-input mt-2" name="venueStatus"><option value="needed">{sw ? "Nahitaji venue" : "Need a venue"}</option><option value="shortlisted">{sw ? "Nimechagua chache" : "Shortlisted"}</option><option value="booked_elsewhere">{sw ? "Nimeshabook" : "Already booked"}</option><option value="booked_kodimali">{sw ? "Nimebook KODIMALI" : "Booked on KODIMALI"}</option></select></label><label className="field-label">{sw ? "Accessibility au usalama" : "Accessibility or safety"}<textarea className="field-input mt-2" name="accessibility" /></label><label className="field-label">{sw ? "Mpango wa hali ya hewa" : "Weather contingency"}<textarea className="field-input mt-2" name="weather" /></label><button className="btn btn-success sm:col-span-2" disabled={busy}>{busy ? (sw ? "Inaandaa…" : "Preparing…") : (sw ? "Tengeneza mapendekezo" : "Create recommendations")}</button></form></div>{notice ? <p className="mt-5 rounded-2xl bg-brand-info-soft p-4 font-semibold">{notice}</p> : null}{recommendations.length ? <div className="mt-6 grid gap-3 sm:grid-cols-2">{recommendations.map((row) => <article className="soft-panel p-4" key={String(row.id)}><h3 className="font-semibold">{String(sw ? row.title_sw : row.title_en).replaceAll("_", " ")}</h3><p className="mt-2 text-sm text-muted">{String(sw ? row.reason_sw : row.reason_en)}</p>{row.suggested_quantity ? <p className="mt-2 font-bold">{sw ? "Idadi ya kuanzia" : "Starting quantity"}: {String(row.suggested_quantity)}</p> : null}<p className="mt-2 text-xs text-muted">{String(row.estimate_source)}</p></article>)}</div> : null}{recommendations.length ? <Link href="/account#event-plans" className="btn btn-outline mt-6">{sw ? "Fungua Event Control Center" : "Open Event Control Center"}</Link> : null}</section>;
}
