"use client";

import { FormEvent, useEffect, useState } from "react";
import Link from "next/link";
import { EventLocationFields } from "@/components/event-location-fields";
import { useLanguage } from "@/components/language-provider";
import { getBrowserSupabase } from "@/lib/supabase-browser";

type Row = Record<string, unknown>;

export function EventPlanBuilder() {
  const { language } = useLanguage();
  const sw = language === "sw";
  const supabase = getBrowserSupabase();
  const [types, setTypes] = useState<Row[]>([]);
  const [equipment, setEquipment] = useState<Row[]>([]);
  const [services, setServices] = useState<Row[]>([]);
  const [locationId, setLocationId] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  useEffect(() => {
    void Promise.all([
      supabase
        .from("event_types")
        .select("id,name_sw,name_en")
        .eq("is_approved", true)
        .order("display_order"),
      supabase.rpc("search_public_event_equipment", {
        p_search: null,
        p_category_id: null,
        p_location_id: locationId || null,
        p_start_at: null,
        p_end_at: null,
        p_min_price: null,
        p_max_price: null,
        p_sort: "recommended",
        p_limit: 50,
        p_offset: 0,
      } as never),
      supabase.rpc("search_public_event_services", {
        p_search: null,
        p_provider_kind: null,
        p_location_id: locationId || null,
        p_start_at: null,
        p_end_at: null,
        p_min_price: null,
        p_max_price: null,
        p_sort: "recommended",
        p_limit: 50,
        p_offset: 0,
      } as never),
    ]).then(([a, b, c]) => {
      setTypes((a.data ?? []) as Row[]);
      setEquipment((b.data ?? []) as Row[]);
      setServices((c.data ?? []) as Row[]);
    });
  }, [supabase, locationId]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setNotice("");
    const form = new FormData(event.currentTarget);
    const hasSelection =
      equipment.some((item) => form.get(`equipment-${item.id}`) === "on") ||
      services.some((item) => form.get(`service-${item.id}`) === "on");
    if (!hasSelection) {
      setBusy(false);
      setNotice(
        sw
          ? "Chagua angalau kifaa au huduma."
          : "Choose at least one item or service.",
      );
      return;
    }
    const { data: auth } = await supabase.auth.getUser();
    if (!auth.user) {
      window.location.assign("/login?next=/events/plan");
      return;
    }
    const start = new Date(String(form.get("start")));
    const end = new Date(String(form.get("end")));
    const { data, error } = await supabase.rpc("create_event_plan", {
      p_event_type_id: form.get("eventType"),
      p_start_at: start.toISOString(),
      p_end_at: end.toISOString(),
      p_location_id: locationId,
      p_private_location_details: null,
      p_attendance: 1,
      p_budget_tzs: null,
      p_title: form.get("title"),
    } as never);
    const plan = data as unknown as Row | null;
    if (error || !plan?.id) {
      setBusy(false);
      setNotice(
        error?.message ??
          (sw ? "Mpango haukuhifadhiwa." : "The plan could not be saved."),
      );
      return;
    }
    let count = 0;
    for (const item of equipment) {
      if (form.get(`equipment-${item.id}`) !== "on") continue;
      const { error: itemError } = await supabase.rpc("add_event_plan_item", {
        p_plan_id: plan.id,
        p_item_kind: "equipment",
        p_equipment_id: item.id,
        p_offering_id: null,
        p_quantity: Math.max(1, Number(form.get(`quantity-${item.id}`)) || 1),
        p_required: true,
        p_requirements: null,
      } as never);
      if (itemError) {
        setBusy(false);
        setNotice(itemError.message);
        return;
      }
      count++;
    }
    for (const service of services) {
      if (form.get(`service-${service.id}`) !== "on") continue;
      const { error: itemError } = await supabase.rpc("add_event_plan_item", {
        p_plan_id: plan.id,
        p_item_kind: "service",
        p_equipment_id: null,
        p_offering_id: service.id,
        p_quantity: null,
        p_required: true,
        p_requirements: null,
      } as never);
      if (itemError) {
        setBusy(false);
        setNotice(itemError.message);
        return;
      }
      count++;
    }
    if (!count) {
      setBusy(false);
      setNotice(
        sw
          ? "Chagua angalau kifaa au huduma."
          : "Choose at least one item or service.",
      );
      return;
    }
    const { error: quoteError } = await supabase.rpc("request_event_quote", {
      p_plan_id: plan.id,
    } as never);
    setBusy(false);
    setNotice(
      quoteError?.message ??
        (sw
          ? `Ombi limetumwa: ${String(plan.reference ?? "")}`
          : `Request sent: ${String(plan.reference ?? "")}`),
    );
  }

  return (
    <div className="space-y-7 pb-16">
      <section className="owner-hero rounded-[28px] p-6 text-white sm:p-9">
        <p className="eyebrow !text-brand-amber">
          {sw ? "Panga Tukio" : "Plan an Event"}
        </p>
        <h1 className="mt-3 font-heading text-4xl font-semibold">
          {sw
            ? "Chagua huduma, kisha omba quotation moja."
            : "Choose services, then request one quotation."}
        </h1>
        <p className="mt-3 max-w-2xl text-white/70">
          {sw
            ? "Hapa unachagua matangazo halisi ya vifaa na wataalamu yaliyopo kwenye KODIMALI Events."
            : "Choose real equipment and professional listings published in KODIMALI Events."}
        </p>
        <Link
          href="/events"
          className="btn btn-outline mt-5 !border-white/30 !bg-white/10 !text-white"
        >
          {sw ? "Rudi kwenye matangazo" : "Back to listings"}
        </Link>
      </section>
      <form className="surface-card grid gap-6 p-5 sm:p-8" onSubmit={submit}>
        <section className="order-3 grid gap-4 border-t border-black/5 pt-6 sm:grid-cols-2">
          <div className="sm:col-span-2">
            <p className="eyebrow">{sw ? "Hatua ya 2" : "Step 2"}</p>
            <h2 className="mt-2 font-heading text-2xl font-semibold">
              {sw ? "Tarehe na eneo la tukio" : "Event date and location"}
            </h2>
            <p className="mt-1 text-sm text-muted">
              {sw
                ? "Tunaomba maelezo haya baada ya kuchagua unachohitaji ili kuthibitisha upatikanaji na quotation."
                : "We ask for these details after your selections to confirm availability and prepare the quote."}
            </p>
          </div>
          <label className="field-label sm:col-span-2">
            {sw ? "Jina la tukio (si lazima)" : "Event name (optional)"}
            <input className="field-input mt-2" name="title" />
          </label>
          <label className="field-label sm:col-span-2">
            {sw ? "Aina ya tukio" : "Event type"}
            <select className="field-input mt-2" name="eventType" required>
              <option value="">{sw ? "Chagua" : "Choose"}</option>
              {types.map((row) => (
                <option key={String(row.id)} value={String(row.id)}>
                  {String(sw ? row.name_sw : row.name_en)}
                </option>
              ))}
            </select>
          </label>
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
          <div className="sm:col-span-2">
            <p className="field-label mb-2">
              {sw ? "Eneo la tukio" : "Event location"}
            </p>
            <EventLocationFields
              value={locationId}
              onChange={setLocationId}
              required
            />
          </div>
        </section>
        <fieldset className="event-filter-group order-1">
          <legend>
            {sw ? "Hatua ya 1 · Chagua vifaa" : "Step 1 · Choose equipment"}
          </legend>
          <div className="grid gap-3 sm:grid-cols-2">
            {equipment.map((item) => (
              <div
                className="flex items-center gap-3 rounded-2xl border border-black/10 bg-brand-card-soft p-4 transition hover:-translate-y-0.5 hover:border-brand-teal"
                key={String(item.id)}
              >
                <label className="flex min-w-0 flex-1 items-center gap-2">
                  <input type="checkbox" name={`equipment-${item.id}`} />
                  <span className="truncate font-semibold">
                    {String(item.name)}
                  </span>
                </label>
                <input
                  className="field-input !w-20"
                  name={`quantity-${item.id}`}
                  type="number"
                  min="1"
                  max={Number(item.available_quantity ?? item.total_quantity)}
                  defaultValue="1"
                  aria-label={`${String(item.name)} quantity`}
                />
              </div>
            ))}
          </div>
        </fieldset>
        <fieldset className="event-filter-group order-2">
          <legend>{sw ? "Chagua wataalamu" : "Choose professionals"}</legend>
          <div className="grid gap-3 sm:grid-cols-2">
            {services.map((item) => {
              return (
                <label
                  className="flex items-center gap-3 rounded-2xl border border-black/10 bg-brand-card-soft p-4 transition hover:-translate-y-0.5 hover:border-brand-teal"
                  key={String(item.id)}
                >
                  <input type="checkbox" name={`service-${item.id}`} />
                  <span>
                    <strong>{String(item.title)}</strong>
                    <small className="block text-muted">
                      {String(item.display_name ?? "")}
                    </small>
                  </span>
                </label>
              );
            })}
          </div>
        </fieldset>
        <button
          className="btn btn-success order-4"
          disabled={busy || !locationId}
        >
          {busy
            ? sw
              ? "Inatuma…"
              : "Sending…"
            : sw
              ? "Omba quotation moja"
              : "Request one quotation"}
        </button>
        {notice ? (
          <p
            className="order-5 rounded-2xl bg-brand-info-soft p-4 font-semibold"
            role="status"
          >
            {notice}
          </p>
        ) : null}
      </form>
    </div>
  );
}
