"use client";
import { UiText } from "@/components/ui-text";

import Link from "next/link";
import { FormEvent, useMemo, useState } from "react";
import { SupervisorLocationChoice } from "@/components/supervisor-territories";
import { agentRegistrationError } from "@/lib/agent-registration-error";
import { getBrowserSupabase, getRegistrationSupabase } from "@/lib/supabase-browser";

type Option = { id: string; name: string; slug?: string; location_type?: string };

export function AgentRegistrationForm({ categories, initialCategoryId = "", staffCreation = false, onCreated, assignedLocation }: { categories: Option[]; regions: Option[]; initialCategoryId?: string; staffCreation?: boolean; onCreated?: () => void; assignedLocation?: Option }) {
  const supabase = getBrowserSupabase();
  const [operatingLocation, setOperatingLocation] = useState(assignedLocation?.location_type === "area" ? assignedLocation.id : "");
  const [areaDraft, setAreaDraft] = useState<{ wardId: string; name: string } | null>(null);
  const assignedId = assignedLocation?.id;
  const assignedName = assignedLocation?.name;
  const assignedType = assignedLocation?.location_type;
  const root = useMemo(() => assignedId ? { id: assignedId, name: assignedName ?? "", location_type: assignedType ?? "territory" } : undefined, [assignedId, assignedName, assignedType]);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const [complete, setComplete] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setNotice("");
    const form = new FormData(event.currentTarget);
    const password = String(form.get("password") ?? "");
    const confirm = String(form.get("confirmPassword") ?? "");
    if (password !== confirm) { setBusy(false); setNotice("Passwords do not match."); return; }
    if (!operatingLocation && !areaDraft?.name.trim()) { setBusy(false); setNotice("Please choose your region, district, ward and operating area before continuing."); return; }
    let locationId = operatingLocation;
    try {
      if (!locationId && areaDraft) {
        const result = await supabase.rpc("ensure_ward_area", { p_ward_id: areaDraft.wardId, p_area_name: areaDraft.name.trim() } as never).abortSignal(AbortSignal.timeout(10000));
        if (result.error) throw result.error;
        const area = result.data?.[0] as { id?: string; parent_id?: string; location_type?: string } | undefined;
        if (!area?.id || area.parent_id !== areaDraft.wardId || area.location_type !== "area") throw new Error("Area could not be saved");
        locationId = area.id;
        setOperatingLocation(locationId);
      }
    } catch (error) { setNotice(agentRegistrationError(error)); setBusy(false); return; }
    if (staffCreation) {
      try {
        const { error } = await supabase.functions.invoke("create-agent-account", { signal: AbortSignal.timeout(20000), body: {
          username: String(form.get("username") ?? "").trim().toLowerCase(), password,
          full_name: String(form.get("fullName") ?? "").trim(),
          phone_number: String(form.get("phone") ?? "").trim(),
          location_id: locationId,
          nida_number: String(form.get("nida") ?? "").trim().toUpperCase(),
          business_name: String(form.get("businessName") ?? "").trim(),
          business_description: String(form.get("description") ?? "").trim(),
          primary_category_id: String(form.get("categoryId") ?? ""), preferred_language: "sw",
        } });
        if (error) {
          const response = (error as { context?: Response }).context;
          const payload = response ? await response.clone().json().catch(() => null) : null;
          throw new Error(payload?.error ?? error.message);
        }
        setComplete(true); setNotice("Agent account created. Review and activate the agent when verification is complete.");
        onCreated?.();
      } catch (error) {
        setNotice(agentRegistrationError(error));
      } finally { setBusy(false); }
      return;
    }
    try {
      const { error } = await getRegistrationSupabase().auth.signUp({
        email: String(form.get("email") ?? "").trim(), password,
        options: { emailRedirectTo: `${window.location.origin}/manage`, data: {
          full_name: String(form.get("fullName") ?? "").trim(),
          username: String(form.get("username") ?? "").trim().toLowerCase(),
          phone_number: String(form.get("phone") ?? "").trim(),
          preferred_language: "sw", register_as_agent: true,
          registration_source: "agent_self_register_web",
          location_id: locationId,
          nida_number: String(form.get("nida") ?? "").trim().toUpperCase(),
          business_name: String(form.get("businessName") ?? "").trim(),
          business_description: String(form.get("description") ?? "").trim(),
          primary_category_id: String(form.get("categoryId") ?? ""),
        } },
      });
      setBusy(false);
      if (error) { setNotice(agentRegistrationError(error)); return; }
      // The isolated registration client never stores or replaces a login session.
      setComplete(true); setNotice("Agent application submitted. Confirm your email if requested, then wait for administrator approval.");
    } catch (error) { setNotice(agentRegistrationError(error)); } finally { setBusy(false); }
  }

  if (complete && staffCreation) return <p className="soft-panel p-4" role="status"><UiText text={notice} /></p>;

  if (complete) return <section className="surface-card mx-auto max-w-2xl p-8"><p className="eyebrow"><UiText text={"Application received"} /></p><h1 className="mt-3 font-heading text-3xl font-semibold"><UiText text={"Agent registration submitted"} /></h1><p className="mt-4 text-muted"><UiText text={notice} /></p><Link className="btn btn-success mt-6" href="/manage"><UiText text={"Return to Manage login"} /></Link></section>;

  return <div className={staffCreation ? "mt-5" : "grid gap-8 py-10 lg:grid-cols-[0.75fr_1.25fr]"}>{!staffCreation && <section className="owner-hero h-fit rounded-[28px] p-8 text-white"><p className="eyebrow !text-brand-amber"><UiText text={"Agent registration"} /></p><h1 className="mt-3 font-heading text-4xl font-semibold"><UiText text={"Join KODIMALI Manage"} /></h1><p className="mt-4 text-white/75"><UiText text={"Submit your identity, service category and operating location. Hall agents should choose Meeting Hall or Ceremony Hall. Access opens after administrator verification."} /></p><Link href="/manage" className="btn btn-outline mt-6"><UiText text={"Already registered? Sign in"} /></Link></section>}<form className="surface-card grid gap-4 p-6 sm:grid-cols-2 sm:p-8" onSubmit={submit}><h2 className="font-heading text-2xl font-semibold sm:col-span-2"><UiText text={"Agent details"} /></h2><Field name="fullName" label="Full name" autoComplete="name" /><Field name="username" label="Username" pattern="[a-z0-9_]{3,32}" />{!staffCreation && <Field name="email" label="Email" type="email" autoComplete="email" />}<Field name="phone" label="Phone number" type="tel" autoComplete="tel" /><Field name="nida" label="NIDA number" /><Field name="businessName" label="Business name" /><label className="field-label"><UiText text={"Primary category"} /><select className="field-input mt-2" name="categoryId" defaultValue={initialCategoryId} required><option value=""><UiText text={"Choose category"} /></option>{categories.map((item)=><option key={item.id} value={item.id}><UiText text={item.name} /></option>)}</select></label><div className="sm:col-span-2"><input type="hidden" name="locationId" value={operatingLocation} /><SupervisorLocationChoice root={root} requireArea onChange={setOperatingLocation} onAreaDraftChange={setAreaDraft} /></div><label className="field-label sm:col-span-2"><UiText text={"Business description"} /><textarea className="field-input mt-2 min-h-24" name="description" /></label><Field name="password" label="Password" type="password" minLength={6} autoComplete="new-password" /><Field name="confirmPassword" label="Confirm password" type="password" minLength={6} autoComplete="new-password" /><button className="btn btn-success sm:col-span-2" disabled={busy || (!operatingLocation && !areaDraft?.name.trim())}><UiText text={busy ? "Submitting..." : staffCreation ? "Create agent account" : "Submit agent registration"} /></button>{notice ? <p className="manage-login-feedback sm:col-span-2" role="status"><UiText text={notice} /></p> : null}</form></div>;
}

function Field({ label, ...inputProps }: { name:string;label:string;type?:string;pattern?:string;minLength?:number;autoComplete?:string }) { return <label className="field-label"><UiText text={label} /><input className="field-input mt-2" required {...inputProps} /></label>; }
