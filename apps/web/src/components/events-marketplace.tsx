"use client";

import { FormEvent, useEffect, useState } from "react";
import Link from "next/link";
import { getBrowserSupabase } from "@/lib/supabase-browser";
import { useLanguage } from "@/components/language-provider";
import { RevealOnScroll } from "@/components/motion/reveal-on-scroll";
import { EventsPublicCatalog } from "@/components/events-public-catalog";
import { EventAdvisor } from "@/components/event-advisor";
import { EventLocationFields } from "@/components/event-location-fields";

type Row = Record<string, unknown>;

export function EventsMarketplace() {
  const { language } = useLanguage();
  const sw = language === "sw";
  const supabase = getBrowserSupabase();
  const [types, setTypes] = useState<Row[]>([]);
  const [equipment, setEquipment] = useState<Row[]>([]);
  const [services, setServices] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const [notice, setNotice] = useState("");
  const [busy, setBusy] = useState(false);
  const [planLocationId, setPlanLocationId] = useState("");

  useEffect(() => {
    let active = true;
    void Promise.all([
      supabase
        .from("event_types")
        .select("id,slug,name_sw,name_en,description_sw,description_en")
        .eq("is_approved", true)
        .order("display_order"),
      supabase
        .from("event_equipment_items")
        .select(
          "id,name,description,total_quantity,price_amount_tzs,price_unit,event_equipment_categories(name_sw,name_en)",
        )
        .eq("verification_status", "verified")
        .eq("is_active", true)
        .limit(12),
      supabase
        .from("event_service_profiles")
        .select("id,display_name,provider_kind,biography,experience_years")
        .eq("verification_status", "verified")
        .eq("is_active", true)
        .limit(12),
    ]).then(([typeResult, equipmentResult, serviceResult]) => {
      if (!active) return;
      setTypes((typeResult.data ?? []) as Row[]);
      setEquipment((equipmentResult.data ?? []) as Row[]);
      setServices((serviceResult.data ?? []) as Row[]);
      setLoading(false);
    });
    return () => {
      active = false;
    };
  }, [supabase]);

  async function createPlan(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const formElement = event.currentTarget;
    setBusy(true);
    setNotice("");
    const form = new FormData(formElement);
    const { data: auth } = await supabase.auth.getUser();
    if (!auth.user) {
      window.location.assign("/login?next=/events#plan-event");
      return;
    }
    const start = new Date(String(form.get("start")));
    const end = new Date(String(form.get("end")));
    const { data, error } = await supabase.rpc("create_event_plan", {
      p_event_type_id: form.get("eventType"),
      p_start_at: start.toISOString(),
      p_end_at: end.toISOString(),
      p_location_id: planLocationId,
      p_private_location_details: null,
      p_attendance: Number(form.get("attendance")),
      p_budget_tzs: Number(form.get("budget")) || null,
      p_title: form.get("title"),
    } as never);
    const result = data as unknown as Row | null;
    if (error || !result?.id) {
      setBusy(false);
      setNotice(
        error?.message ??
          (sw
            ? "Mpango haukuhifadhiwa."
            : "The event plan could not be saved."),
      );
      return;
    }
    for (const item of equipment) {
      if (form.get(`equipment-${String(item.id)}`) !== "on") continue;
      const { error: itemError } = await supabase.rpc("add_event_plan_item", {
        p_plan_id: result.id,
        p_item_kind: "equipment",
        p_equipment_id: item.id,
        p_offering_id: null,
        p_quantity: Math.max(
          1,
          Number(form.get(`quantity-${String(item.id)}`)) || 1,
        ),
        p_required: true,
        p_requirements: null,
      } as never);
      if (itemError) {
        setBusy(false);
        setNotice(itemError.message);
        return;
      }
    }
    for (const provider of services) {
      if (form.get(`service-${String(provider.id)}`) !== "on") continue;
      const { data: offering } = await supabase
        .from("event_service_offerings")
        .select("id")
        .eq("provider_id", String(provider.id))
        .eq("is_active", true)
        .limit(1)
        .maybeSingle();
      if (!offering) continue;
      const offeringRow = offering as unknown as Row;
      const { error: itemError } = await supabase.rpc("add_event_plan_item", {
        p_plan_id: result.id,
        p_item_kind: "service",
        p_equipment_id: null,
        p_offering_id: offeringRow.id,
        p_quantity: null,
        p_required: true,
        p_requirements: null,
      } as never);
      if (itemError) {
        setBusy(false);
        setNotice(itemError.message);
        return;
      }
    }
    const { error: quoteError } = await supabase.rpc("request_event_quote", {
      p_plan_id: result.id,
    } as never);
    setBusy(false);
    setNotice(
      quoteError?.message ??
        (sw
          ? `Ombi la quotation limetumwa: ${String(result.reference ?? "")}`
          : `Quotation request sent: ${String(result.reference ?? "")}`),
    );
    if (!quoteError) formElement.reset();
  }

  return (
    <div className="space-y-12 pb-16">
      <section className="owner-hero relative overflow-hidden rounded-[32px] p-7 text-white sm:p-12">
        <div className="absolute -right-20 -top-24 h-72 w-72 rounded-full bg-brand-amber/20 blur-3xl" />
        <p className="eyebrow !text-brand-amber">KODIMALI Events</p>
        <h1 className="mt-4 max-w-4xl font-heading text-4xl font-semibold sm:text-6xl">
          {sw
            ? "Panga sherehe yako, sehemu moja."
            : "Plan your event in one place."}
        </h1>
        <p className="mt-5 max-w-2xl text-lg text-white/75">
          {sw
            ? "Kodisha vifaa, chagua wataalamu na omba quotation moja yenye gharama zilizoainishwa."
            : "Rent equipment, choose professionals and request one itemized quotation."}
        </p>
        <a href="#plan-event" className="btn btn-success mt-7">
          {sw ? "Anza kupanga" : "Start planning"}
        </a>
      </section>

      <nav
        className="surface-card flex flex-wrap gap-2 p-3"
        aria-label={sw ? "Urambazaji wa Events" : "Events navigation"}
      >
        <a className="btn btn-outline" href="#individual-marketplace">
          {sw ? "Vifaa" : "Explore Equipment"}
        </a>
        <a className="btn btn-outline" href="#individual-marketplace">
          {sw ? "Wataalamu" : "Find Professionals"}
        </a>
        <a className="btn btn-outline" href="#advisor">
          {sw ? "Mshauri wa Tukio" : "Event Advisor"}
        </a>
        <a className="btn btn-outline" href="#plan-event">
          {sw ? "Jenga Event" : "Build an Event"}
        </a>
        <Link className="btn btn-outline" href="/account#event-plans">
          {sw ? "Events Zangu" : "My Events"}
        </Link>
        <Link className="btn btn-outline" href="/account#event-plans">
          {sw ? "Booking Zangu" : "My Bookings"}
        </Link>
      </nav>

      <EventsPublicCatalog />

      <EventAdvisor eventTypes={types} />

      <RevealOnScroll>
        <section>
          <p className="eyebrow">{sw ? "Aina ya tukio" : "Occasion"}</p>
          <h2 className="mt-3 font-heading text-3xl font-semibold">
            {sw ? "Unaandaa tukio gani?" : "What are you organizing?"}
          </h2>
          <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {loading ? (
              <p>{sw ? "Inapakia…" : "Loading…"}</p>
            ) : (
              types.map((type) => (
                <article
                  className="surface-card p-5 transition hover:-translate-y-1"
                  key={String(type.id)}
                >
                  <h3 className="font-heading text-xl font-semibold">
                    {String(sw ? type.name_sw : type.name_en)}
                  </h3>
                  <p className="mt-2 text-sm text-muted">
                    {String(
                      (sw ? type.description_sw : type.description_en) ?? "",
                    )}
                  </p>
                </article>
              ))
            )}
          </div>
        </section>
      </RevealOnScroll>

      <section className="grid gap-8 lg:grid-cols-2">
        <div>
          <p className="eyebrow">{sw ? "Vifaa" : "Equipment"}</p>
          <h2 className="mt-3 font-heading text-3xl font-semibold">
            {sw
              ? "Kodisha kwa idadi unayohitaji"
              : "Rent the quantity you need"}
          </h2>
          <div className="mt-5 grid gap-3">
            {equipment.length === 0 ? (
              <p className="text-muted">
                {sw
                  ? "Hakuna vifaa vilivyothibitishwa kwa sasa."
                  : "No verified equipment yet."}
              </p>
            ) : (
              equipment.map((item) => (
                <article className="soft-panel p-4" key={String(item.id)}>
                  <div className="flex justify-between gap-3">
                    <h3 className="font-semibold">{String(item.name)}</h3>
                    <strong>TZS {String(item.price_amount_tzs)}</strong>
                  </div>
                  <p className="mt-2 text-sm text-muted">
                    {sw ? "Vilivyopo" : "Available stock"}:{" "}
                    {String(item.total_quantity)}
                  </p>
                </article>
              ))
            )}
          </div>
        </div>
        <div>
          <p className="eyebrow">{sw ? "Wataalamu" : "Professionals"}</p>
          <h2 className="mt-3 font-heading text-3xl font-semibold">
            {sw
              ? "Huduma zinazolingana na tukio"
              : "Services matched to your event"}
          </h2>
          <div className="mt-5 grid gap-3">
            {services.length === 0 ? (
              <p className="text-muted">
                {sw
                  ? "Hakuna wataalamu waliothibitishwa kwa sasa."
                  : "No verified professionals yet."}
              </p>
            ) : (
              services.map((provider) => (
                <article className="soft-panel p-4" key={String(provider.id)}>
                  <h3 className="font-semibold">
                    {String(provider.display_name)}
                  </h3>
                  <p className="mt-1 text-sm text-muted">
                    {String(provider.provider_kind).replaceAll("_", " ")} ·{" "}
                    {String(provider.experience_years ?? 0)}{" "}
                    {sw ? "miaka" : "years"}
                  </p>
                </article>
              ))
            )}
          </div>
        </div>
      </section>

      <RevealOnScroll>
        <section id="plan-event" className="surface-card p-6 sm:p-8">
          <p className="eyebrow">{sw ? "Mpango wa tukio" : "Event plan"}</p>
          <h2 className="mt-3 font-heading text-3xl font-semibold">
            {sw ? "Tuanzie kwenye maelezo muhimu" : "Start with the essentials"}
          </h2>
          <form
            className="mt-7 grid gap-5 sm:grid-cols-2"
            onSubmit={createPlan}
          >
            <label className="field-label sm:col-span-2">
              {sw ? "Jina la tukio" : "Event name"}
              <input className="field-input mt-2" name="title" required />
            </label>
            <label className="field-label sm:col-span-2">
              {sw ? "Aina ya tukio" : "Event type"}
              <select className="field-input mt-2" name="eventType" required>
                <option value="">{sw ? "Chagua" : "Choose"}</option>
                {types.map((type) => (
                  <option key={String(type.id)} value={String(type.id)}>
                    {String(sw ? type.name_sw : type.name_en)}
                  </option>
                ))}
              </select>
            </label>
            <div className="soft-panel p-4 sm:col-span-2">
              <p className="field-label mb-3">
                {sw ? "Eneo la tukio" : "Event location"}
              </p>
              <EventLocationFields
                value={planLocationId}
                onChange={setPlanLocationId}
                required
              />
            </div>
            <label className="field-label">
              {sw ? "Mwanzo" : "Starts"}
              <input
                className="field-input mt-2"
                type="datetime-local"
                name="start"
                required
              />
            </label>
            <label className="field-label">
              {sw ? "Mwisho" : "Ends"}
              <input
                className="field-input mt-2"
                type="datetime-local"
                name="end"
                required
              />
            </label>
            <label className="field-label">
              {sw ? "Idadi ya wageni" : "Estimated attendance"}
              <input
                className="field-input mt-2"
                type="number"
                min="1"
                name="attendance"
                required
              />
            </label>
            <label className="field-label">
              {sw ? "Bajeti (TZS)" : "Budget (TZS)"}
              <input
                className="field-input mt-2"
                type="number"
                min="0"
                name="budget"
              />
            </label>
            <fieldset className="soft-panel p-4 sm:col-span-2">
              <legend className="px-2 font-semibold">
                {sw
                  ? "Chagua vifaa na idadi"
                  : "Choose equipment and quantities"}
              </legend>
              <div className="grid gap-3 sm:grid-cols-2">
                {equipment.map((item) => (
                  <div
                    className="flex items-center gap-3"
                    key={String(item.id)}
                  >
                    <label className="flex flex-1 items-center gap-2">
                      <input
                        type="checkbox"
                        name={`equipment-${String(item.id)}`}
                      />
                      <span>{String(item.name)}</span>
                    </label>
                    <input
                      className="field-input !w-24"
                      type="number"
                      min="1"
                      max={Number(item.total_quantity)}
                      defaultValue="1"
                      name={`quantity-${String(item.id)}`}
                      aria-label={`${String(item.name)} quantity`}
                    />
                  </div>
                ))}
              </div>
            </fieldset>
            <fieldset className="soft-panel p-4 sm:col-span-2">
              <legend className="px-2 font-semibold">
                {sw ? "Chagua wataalamu" : "Choose professionals"}
              </legend>
              <div className="grid gap-3 sm:grid-cols-2">
                {services.map((provider) => (
                  <label
                    className="flex items-center gap-2"
                    key={String(provider.id)}
                  >
                    <input
                      type="checkbox"
                      name={`service-${String(provider.id)}`}
                    />
                    <span>
                      {String(provider.display_name)} ·{" "}
                      {String(provider.provider_kind).replaceAll("_", " ")}
                    </span>
                  </label>
                ))}
              </div>
            </fieldset>
            <button
              className="btn btn-success sm:col-span-2"
              disabled={busy || !planLocationId}
            >
              {busy
                ? sw
                  ? "Inahifadhi…"
                  : "Saving…"
                : sw
                  ? "Tuma ombi la quotation"
                  : "Request quotation"}
            </button>
          </form>
          {notice ? (
            <p className="mt-4 rounded-2xl bg-brand-card-soft p-4 font-semibold">
              {notice}
            </p>
          ) : null}
          <p className="mt-4 text-sm text-muted">
            {sw
              ? "Malipo halisi hayajawashwa. Quotation na makubaliano yatathibitishwa kwanza."
              : "Live payment collection remains disabled. Quotations and agreements are reviewed first."}
          </p>
        </section>
      </RevealOnScroll>
      <div className="text-center">
        <Link href="/account" className="btn btn-outline">
          {sw ? "Angalia mipango yangu" : "View my event plans"}
        </Link>
      </div>
    </div>
  );
}
