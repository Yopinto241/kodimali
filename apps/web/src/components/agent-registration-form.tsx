"use client";

import Link from "next/link";
import { FormEvent, useState } from "react";
import { getBrowserSupabase } from "@/lib/supabase-browser";

type Option = { id: string; name: string; slug?: string };

export function AgentRegistrationForm({ categories, regions, initialCategoryId = "" }: { categories: Option[]; regions: Option[]; initialCategoryId?: string }) {
  const supabase = getBrowserSupabase();
  const [districts, setDistricts] = useState<Option[]>([]);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const [complete, setComplete] = useState(false);

  async function loadDistricts(regionId: string) {
    setDistricts([]);
    if (!regionId) return;
    const response = await fetch(`/api/locations?locationType=district&parentId=${encodeURIComponent(regionId)}`);
    setDistricts(await response.json() as Option[]);
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setNotice("");
    const form = new FormData(event.currentTarget);
    const password = String(form.get("password") ?? "");
    const confirm = String(form.get("confirmPassword") ?? "");
    if (password !== confirm) { setBusy(false); setNotice("Passwords do not match."); return; }
    const { data, error } = await supabase.auth.signUp({
      email: String(form.get("email") ?? "").trim(), password,
      options: { emailRedirectTo: `${window.location.origin}/manage`, data: {
        full_name: String(form.get("fullName") ?? "").trim(),
        username: String(form.get("username") ?? "").trim().toLowerCase(),
        phone_number: String(form.get("phone") ?? "").trim(),
        preferred_language: "sw", register_as_agent: true,
        registration_source: "agent_self_register_web",
        location_id: String(form.get("districtId") ?? ""),
        nida_number: String(form.get("nida") ?? "").trim().toUpperCase(),
        business_name: String(form.get("businessName") ?? "").trim(),
        business_description: String(form.get("description") ?? "").trim(),
        primary_category_id: String(form.get("categoryId") ?? ""),
      } },
    });
    setBusy(false);
    if (error) { setNotice(error.message); return; }
    if (data.session) await supabase.auth.signOut();
    setComplete(true); setNotice("Agent application submitted. Confirm your email if requested, then wait for administrator approval.");
  }

  if (complete) return <section className="surface-card mx-auto max-w-2xl p-8"><p className="eyebrow">Application received</p><h1 className="mt-3 font-heading text-3xl font-semibold">Agent registration submitted</h1><p className="mt-4 text-muted">{notice}</p><Link className="btn btn-success mt-6" href="/manage">Return to Manage login</Link></section>;

  return <div className="grid gap-8 py-10 lg:grid-cols-[0.75fr_1.25fr]"><section className="owner-hero h-fit rounded-[28px] p-8 text-white"><p className="eyebrow !text-brand-amber">Agent registration</p><h1 className="mt-3 font-heading text-4xl font-semibold">Join KODIMALI Manage</h1><p className="mt-4 text-white/75">Submit your identity, service category and operating location. Hall agents should choose Meeting Hall or Ceremony Hall. Access opens after administrator verification.</p><Link href="/manage" className="btn btn-outline mt-6">Already registered? Sign in</Link></section><form className="surface-card grid gap-4 p-6 sm:grid-cols-2 sm:p-8" onSubmit={submit}><h2 className="font-heading text-2xl font-semibold sm:col-span-2">Agent details</h2><Field name="fullName" label="Full name" autoComplete="name" /><Field name="username" label="Username" pattern="[a-z0-9_]{3,32}" /><Field name="email" label="Email" type="email" autoComplete="email" /><Field name="phone" label="Phone number" type="tel" autoComplete="tel" /><Field name="nida" label="NIDA number" /><Field name="businessName" label="Business name" /><label className="field-label">Primary category<select className="field-input mt-2" name="categoryId" defaultValue={initialCategoryId} required><option value="">Choose category</option>{categories.map((item)=><option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label className="field-label">Region<select className="field-input mt-2" name="regionId" required onChange={(event)=>void loadDistricts(event.target.value)}><option value="">Choose region</option>{regions.map((item)=><option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label className="field-label sm:col-span-2">District<select className="field-input mt-2" name="districtId" required><option value="">Choose district</option>{districts.map((item)=><option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label className="field-label sm:col-span-2">Business description<textarea className="field-input mt-2 min-h-24" name="description" /></label><Field name="password" label="Password" type="password" minLength={6} autoComplete="new-password" /><Field name="confirmPassword" label="Confirm password" type="password" minLength={6} autoComplete="new-password" /><button className="btn btn-success sm:col-span-2" disabled={busy}>{busy ? "Submitting..." : "Submit agent registration"}</button>{notice ? <p className="rounded-2xl bg-brand-info-soft p-4 text-sm sm:col-span-2" role="status">{notice}</p> : null}</form></div>;
}

function Field({ label, ...inputProps }: { name:string;label:string;type?:string;pattern?:string;minLength?:number;autoComplete?:string }) { return <label className="field-label">{label}<input className="field-input mt-2" required {...inputProps} /></label>; }
