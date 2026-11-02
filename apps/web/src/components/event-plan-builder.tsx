"use client";
import { UiButton, UiNav, UiSelect, UiText } from "@/components/ui-text";
import { FormEvent, useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useNavigate } from "@/components/navigation-progress";
import { EventLocationFields } from "@/components/event-location-fields";
import { EventCardImage } from "@/components/event-card-image";
import { useLanguage } from "@/components/language-provider";
import { getBrowserSupabase } from "@/lib/supabase-browser";
import {
  eventPrice,
  serviceKinds,
  serviceLabel,
  validEventPeriod,
} from "@/lib/event-display";
type Row = Record<string, unknown>;
type Choice = {
  kind: "equipment" | "service";
  id: string;
  name: string;
  quantity: number;
  price: string;
};
type Draft = {
  title: string;
  eventType: string;
  start: string;
  end: string;
  locationId: string;
  locationLabel: string;
  choices: Choice[];
};
const empty: Draft = {
  title: "",
  eventType: "",
  start: "",
  end: "",
  locationId: "",
  locationLabel: "",
  choices: [],
};
const storageKey = "kodimali-event-draft-v2";
function isFutureEventDate(value: string) { return Date.parse(value) > Date.now(); }
export function EventPlanBuilder() {
  const navigate = useNavigate();
  const { language } = useLanguage();
  const sw = language === "sw";
  const db = getBrowserSupabase();
  const [draft, setDraft] = useState<Draft>(empty);
  const [ready, setReady] = useState(false);
  const [saved, setSaved] = useState(true);
  const [step, setStep] = useState(0);
  const [types, setTypes] = useState<Row[]>([]);
  const [equipment, setEquipment] = useState<Row[]>([]);
  const [services, setServices] = useState<Row[]>([]);
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");
  const [category, setCategory] = useState("");
  const [categories, setCategories] = useState<Row[]>([]);
  const [kind, setKind] = useState<"equipment" | "service">("equipment");
  const [offset, setOffset] = useState(0);
  const [more, setMore] = useState(false);
  const [catalogBusy, setCatalogBusy] = useState(false);
  const [catalogError, setCatalogError] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const [success, setSuccess] = useState("");
  const [errors, setErrors] = useState<Record<string, string>>({});
  const catalogRequest = useRef(0);
  const submission = useRef<{ payload: string; key: string } | null>(null);
  const [checks, setChecks] = useState<Row[]>([]);
  const [checkedFor, setCheckedFor] = useState("");
  const set = (key: keyof Draft, value: string) => {
    setDraft((old) => ({ ...old, [key]: value }));
    setErrors((old) => ({ ...old, [key]: "" }));
  };
  useEffect(() => {
    const task = window.setTimeout(() => {
    try {
      const text = localStorage.getItem(storageKey);
      if (text) {
        const parsed = JSON.parse(text);
        if (parsed.version === 2 && Array.isArray(parsed.draft?.choices)) {
          setDraft({ ...empty, ...parsed.draft });
          if (parsed.submission?.key) submission.current = parsed.submission;
        }
      }
    } catch {
      setSaved(false);
    }
    setReady(true);
    }, 0);
    return () => window.clearTimeout(task);
  }, []);
  useEffect(() => {
    if (!ready || success) return;
    const task = window.setTimeout(() => {
    try {
      localStorage.setItem(
        storageKey,
        JSON.stringify({ version: 2, draft, submission: submission.current }),
      );
      setSaved(true);
    } catch {
      setSaved(false);
    }
    }, 0);
    return () => window.clearTimeout(task);
  }, [draft, ready, success]);
  useEffect(() => {
    let active = true;
    void Promise.all([
      db
        .from("event_types")
        .select("id,name_sw,name_en")
        .eq("is_approved", true)
        .neq("slug", "individual-booking")
        .order("display_order"),
      db
        .from("event_equipment_categories")
        .select("id,name_sw,name_en")
        .eq("is_active", true)
        .order("display_order"),
    ]).then(([a, b]) => {
      if (!active) return;
      if (a.error || b.error) setCatalogError((a.error ?? b.error)!.message);
      else {
        setTypes((a.data ?? []) as Row[]);
        setCategories((b.data ?? []) as Row[]);
      }
    });
    return () => {
      active = false;
    };
  }, [db]);
  useEffect(() => {
    const timer = setTimeout(() => {
      setQuery(search);
      setOffset(0);
    }, 300);
    return () => clearTimeout(timer);
  }, [search]);
  const load = useCallback(async () => {
    if (!ready) return;
    const request = ++catalogRequest.current;
    setCatalogBusy(true);
    setCatalogError("");
    try {
      const dated = validEventPeriod(draft.start, draft.end);
      const base = {
        p_search: query.trim() || null,
        p_location_id: draft.locationId || null,
        p_start_at: dated ? new Date(draft.start).toISOString() : null,
        p_end_at: dated ? new Date(draft.end).toISOString() : null,
        p_min_price: null,
        p_max_price: null,
        p_sort: "recommended",
        p_limit: 31,
        p_offset: offset,
      };
      const r = await db.rpc(
        kind === "equipment"
          ? "search_public_event_equipment"
          : "search_public_event_services",
        {
          ...base,
          ...(kind === "equipment"
            ? { p_category_id: category || null }
            : { p_provider_kind: category || null }),
        } as never,
      );
      if (r.error) throw r.error;
      if (request !== catalogRequest.current) return;
      const rows = (r.data ?? []) as Row[];
      if (kind === "equipment") setEquipment(rows.slice(0, 30));
      else setServices(rows.slice(0, 30));
      setMore(rows.length > 30);
    } catch (e) {
      if (request === catalogRequest.current)
        setCatalogError(String((e as Row).message ?? e));
    } finally {
      if (request === catalogRequest.current) setCatalogBusy(false);
    }
  }, [
    ready,
    db,
    draft.start,
    draft.end,
    draft.locationId,
    query,
    category,
    kind,
    offset,
  ]);
  useEffect(() => {
    const requestRef = catalogRequest;
    const task = window.setTimeout(() => { void load(); }, 0);
    return () => {
      window.clearTimeout(task);
      requestRef.current++;
    };
  }, [load]);
  const fingerprint = JSON.stringify([
    draft.start,
    draft.end,
    draft.locationId,
    draft.choices.map((c) => [c.kind, c.id, c.quantity]),
  ]);
  function detailsValid() {
    const e: Record<string, string> = {};
    if (!draft.eventType)
      e.eventType = sw ? "Chagua aina ya tukio." : "Choose an event type.";
    if (
      !draft.start ||
      !Number.isFinite(Date.parse(draft.start)) ||
      !isFutureEventDate(draft.start)
    )
      e.start = sw
        ? "Chagua tarehe na saa ya baadaye."
        : "Choose a future date and time.";
    if (!validEventPeriod(draft.start, draft.end))
      e.end = sw
        ? "Mwisho uwe baada ya mwanzo."
        : "End must be after the start.";
    if (!draft.locationId)
      e.locationId = sw
        ? "Chagua eneo la tukio."
        : "Choose the event location.";
    setErrors(e);
    return Object.keys(e).length === 0;
  }
  async function go(next: number) {
    setNotice("");
    if (next > 0 && !detailsValid()) {
      setStep(0);
      return;
    }
    if (next === 2) {
      if (!draft.choices.length) {
        setNotice(
          sw
            ? "Chagua angalau kifaa au huduma."
            : "Choose at least one item or service.",
        );
        setStep(1);
        return;
      }
      if (
        draft.choices.length > 100 ||
        draft.choices.some(
          (c) =>
            c.kind === "equipment" &&
            (!Number.isInteger(c.quantity) || c.quantity < 1),
        )
      ) {
        setNotice(
          sw
            ? "Chagua hadi mahitaji 100 na idadi kamili iliyo zaidi ya sifuri."
            : "Choose up to 100 items and use whole quantities greater than zero.",
        );
        return;
      }
      setBusy(true);
      try {
        const r = await db.rpc("check_public_event_selection", {
          p_items: draft.choices.map((c) => ({
            kind: c.kind,
            id: c.id,
            quantity: c.quantity,
          })),
          p_start_at: new Date(draft.start).toISOString(),
          p_end_at: new Date(draft.end).toISOString(),
          p_location_id: draft.locationId,
        } as never);
        if (r.error) throw r.error;
        setChecks((r.data ?? []) as Row[]);
        setCheckedFor(fingerprint);
        setStep(2);
      } catch (e) {
        setNotice(String((e as Row).message ?? e));
      } finally {
        setBusy(false);
      }
      return;
    }
    setStep(next);
    window.scrollTo({ top: 0, behavior: "smooth" });
  }
  function toggle(item: Row) {
    const id = String(kind === "equipment" ? item.id : item.offering_id);
    setDraft((old) => ({
      ...old,
      choices: old.choices.some((c) => c.id === id && c.kind === kind)
        ? old.choices.filter((c) => !(c.id === id && c.kind === kind))
        : [
            ...old.choices,
            {
              id,
              kind,
              name: String(item.name ?? item.title),
              quantity: 1,
              price: eventPrice(item, sw),
            },
          ],
    }));
  }
  const blocked =
    checkedFor !== fingerprint ||
    checks.length !== draft.choices.length ||
    checks.some((c) => c.is_available !== true);
  async function submit(event: FormEvent) {
    event.preventDefault();
    if (busy) return;
    if (step !== 2) {
      await go(step + 1);
      return;
    }
    if (!detailsValid()) {
      setStep(0);
      return;
    }
    if (blocked) {
      await go(2);
      return;
    }
    setBusy(true);
    setNotice("");
    try {
      const request = {
        p_event_type_id: draft.eventType,
        p_start_at: new Date(draft.start).toISOString(),
        p_end_at: new Date(draft.end).toISOString(),
        p_location_id: draft.locationId,
        p_title: draft.title || null,
        p_items: draft.choices.map((c) => ({
          kind: c.kind,
          id: c.id,
          ...(c.kind === "equipment" ? { quantity: c.quantity } : {}),
        })),
      };
      const payload = JSON.stringify(request);
      if (submission.current?.payload !== payload)
        submission.current = { payload, key: crypto.randomUUID() };
      try {
        localStorage.setItem(
          storageKey,
          JSON.stringify({ version: 2, draft, submission: submission.current }),
        );
      } catch {
        setSaved(false);
      }
      const { data: auth } = await db.auth.getUser();
      if (!auth.user) {
        if (!saved)
          throw new Error(
            sw
              ? "Hifadhi haipatikani. Ingia katika kichupo kingine kisha ujaribu tena."
              : "Draft storage is unavailable. Sign in in another tab, then try again.",
          );
        navigate("/login?next=/events/plan");
        return;
      }
      const r = await db.rpc("submit_event_plan", {
        ...request,
        p_idempotency_key: submission.current.key,
      } as never);
      if (r.error) throw r.error;
      setSuccess(String((r.data as Row)?.reference ?? ""));
      try {
        localStorage.removeItem(storageKey);
      } catch {
        /* Successful request remains visible. */
      }
    } catch (e) {
      setNotice(String((e as Row).message ?? e));
    } finally {
      setBusy(false);
    }
  }
  const summary = (
    <>
      <h2 className="text-lg font-bold">
        <UiText text={sw ? "Muhtasari wa tukio" : "Event summary"} />
      </h2>
      <p className="mt-2 text-sm text-muted">
        {draft.title || (sw ? "Tukio lako" : "Your event")}
      </p>
      {draft.start ? (
        <p className="mt-2 text-sm">
          {new Date(draft.start).toLocaleString(sw ? "sw-TZ" : "en-GB", {
            dateStyle: "medium",
            timeStyle: "short",
          })}
          {draft.end
            ? ` - ${new Date(draft.end).toLocaleString(sw ? "sw-TZ" : "en-GB", { dateStyle: "medium", timeStyle: "short" })}`
            : ""}
        </p>
      ) : null}
      <p className="mt-2 text-sm">
        {draft.locationLabel ||
          (draft.locationId
            ? sw
              ? "Eneo limechaguliwa"
              : "Location selected"
            : sw
              ? "Eneo halijachaguliwa"
              : "No location selected")}
      </p>
      <ul className="mt-4 space-y-3">
        {draft.choices.map((c) => (
          <li
            className="border-t border-[#dce6df] pt-3 text-sm"
            key={`${c.kind}:${c.id}`}
          >
            <div className="flex gap-2">
              <span className="event-title flex-1">
                {c.name}
                {c.kind === "equipment" ? ` x ${c.quantity}` : ""}
              </span>
              <UiButton
                type="button"
                className="underline"
                disabled={busy}
                aria-label={`${sw ? "Ondoa" : "Remove"} ${c.name}`}
                onClick={() =>
                  setDraft((old) => ({
                    ...old,
                    choices: old.choices.filter((x) => x !== c),
                  }))
                }
              >
                <UiText text={sw ? "Ondoa" : "Remove"} />
              </UiButton>
            </div>
            <p className="mt-1 text-muted">{c.price}</p>
          </li>
        ))}
      </ul>
      {!draft.choices.length ? (
        <p className="mt-4 text-sm text-muted">
          <UiText text={sw
            ? "Bado hujachagua vifaa au huduma."
            : "No equipment or services selected yet."} />
        </p>
      ) : null}
      <p className="mt-5 border-t border-[#dce6df] pt-4 text-sm text-muted">
        <UiText text={sw
          ? "Huu ni mpango wa kuomba bei. Jumla, usafiri, maandalizi na dhamana vitathibitishwa kwenye quotation kabla ya malipo."
          : "This is a quotation request. Your total, delivery, setup and security deposit will be confirmed in the quotation before payment."} />
      </p>
    </>
  );
  if (success)
    return (
      <div className="events-ui">
        <section className="event-success" role="status">
          <h1 className="text-2xl font-bold">
            <UiText text={sw
              ? "Ombi la quotation limetumwa"
              : "Your quotation request has been sent"} />
          </h1>
          <p className="mt-3">
            <UiText text={sw ? "Namba ya kumbukumbu" : "Reference"} />:{" "}
            <strong>{success}</strong>
          </p>
          <p className="mt-3">
            <UiText text={sw
              ? "Timu itathibitisha mahitaji na upatikanaji. Fuatilia quotation na makubaliano kwenye mipango yako kabla ya kulipa."
              : "The team will confirm your requirements and availability. Follow your plan for the quotation and agreement before paying."} />
          </p>
          <Link
            href="/account?section=events#event-plans"
            className="btn btn-success mt-5"
          >
            <UiText text={sw ? "Angalia mipango yangu" : "View my event plans"} />
          </Link>
        </section>
      </div>
    );
  return (
    <div className="events-ui">
      <header className="event-intro">
        <Link className="text-sm font-semibold underline" href="/events">
          &larr; <UiText text={sw ? "Vifaa na huduma" : "Equipment and services"} />
        </Link>
        <h1 className="mt-3"><UiText text={sw ? "Panga tukio lako" : "Plan your event"} /></h1>
        <p>
          <UiText text={sw
            ? "Chagua mahitaji yako, kagua mpango, kisha omba quotation."
            : "Choose what you need, review your plan, then request a quotation."} />
        </p>
        <p className="text-xs" role="status">
          <UiText text={saved
            ? sw
              ? "Rasimu huhifadhiwa kwenye kivinjari hiki."
              : "Your draft is saved in this browser."
            : sw
              ? "Rasimu haiwezi kuhifadhiwa kwenye kivinjari hiki."
              : "Draft saving is unavailable in this browser."} />
        </p>
      </header>
      <UiNav
        className="event-steps"
        aria-label={sw ? "Hatua za kupanga" : "Planning steps"}
      >
        {(sw
          ? ["Taarifa za tukio", "Vifaa na huduma", "Kagua na utume"]
          : ["Event details", "Equipment & services", "Review & send"]
        ).map((label, i) => (
          <button
            type="button"
            key={label}
            aria-current={step === i ? "step" : undefined}
            disabled={busy}
            onClick={() => void go(i)}
          >
            {i + 1}. <UiText text={label} />
          </button>
        ))}
      </UiNav>
      {notice ? (
        <p className="event-error mb-4" role="alert">
          <UiText text={notice} />
        </p>
      ) : null}
      <form
        onSubmit={submit}
        noValidate
        className="grid min-w-0 gap-6 lg:grid-cols-[minmax(0,1fr)_320px]"
      >
        <div className="min-w-0">
          {step === 0 ? (
            <section className="surface-card grid gap-5 p-5 sm:grid-cols-2">
              <h2 className="text-xl font-bold sm:col-span-2">
                <UiText text={sw ? "Taarifa za tukio" : "Event details"} />
              </h2>
              <label className="field-label sm:col-span-2">
                <UiText text={sw ? "Jina la tukio (si lazima)" : "Event name (optional)"} />
                <input
                  className="field-input mt-2"
                  value={draft.title}
                  maxLength={160}
                  onChange={(e) => set("title", e.target.value)}
                />
              </label>
              <label className="field-label sm:col-span-2">
                <UiText text={sw ? "Aina ya tukio" : "Event type"} />
                <UiSelect
                  aria-label={sw ? "Aina ya tukio" : "Event type"}
                  className="field-input mt-2"
                  value={draft.eventType}
                  aria-invalid={!!errors.eventType}
                  onChange={(e) => set("eventType", e.target.value)}
                >
                  <option value="">
                    <UiText text={sw ? "Chagua aina ya tukio" : "Choose event type"} />
                  </option>
                  {types.map((t) => (
                    <option key={String(t.id)} value={String(t.id)}>
                      {String(sw ? t.name_sw : t.name_en)}
                    </option>
                  ))}
                </UiSelect>
                {errors.eventType ? (
                  <span className="mt-1 block text-sm text-red-800">
                    {errors.eventType}
                  </span>
                ) : null}
              </label>
              {(["start", "end"] as const).map((key) => (
                <label key={key} className="field-label">
                  <UiText text={key === "start"
                    ? sw
                      ? "Tarehe na saa ya kuanza"
                      : "Start date and time"
                    : sw
                      ? "Tarehe na saa ya kumaliza"
                      : "End date and time"} />
                  <input
                    className="field-input mt-2"
                    type="datetime-local"
                    value={draft[key]}
                    aria-invalid={!!errors[key]}
                    onChange={(e) => set(key, e.target.value)}
                  />
                  {errors[key] ? (
                    <span className="mt-1 block text-sm text-red-800">
                      {errors[key]}
                    </span>
                  ) : null}
                </label>
              ))}
              <div className="sm:col-span-2">
                <p className="field-label mb-2">
                  <UiText text={sw ? "Eneo la tukio" : "Event location"} />
                </p>
                <EventLocationFields
                  value={draft.locationId}
                  onChange={(v) => {
                    set("locationId", v);
                    setOffset(0);
                  }}
                  onLabelChange={(v) => set("locationLabel", v)}
                />
                {errors.locationId ? (
                  <p className="mt-1 text-sm text-red-800">
                    {errors.locationId}
                  </p>
                ) : null}
              </div>
            </section>
          ) : null}
          {step === 1 ? (
            <section className="space-y-4">
              <h2 className="text-xl font-bold">
                <UiText text={sw
                  ? "Chagua vifaa na wataalamu"
                  : "Select equipment and professionals"} />
              </h2>
              <p className="text-sm text-muted">
                <UiText text={sw
                  ? "Upatikanaji ni wa muda uliochagua; utathibitishwa kabla ya booking. Chaguo zako hubaki hata ukibadili eneo au kichujio."
                  : "Availability reflects your dates and is confirmed before booking. Your selections stay saved when location or filters change."} />
              </p>
              <div className="grid grid-cols-2 gap-2">
                {(["equipment", "service"] as const).map((k) => (
                  <button
                    type="button"
                    className={`btn ${kind === k ? "btn-success" : "btn-outline"}`}
                    aria-pressed={kind === k}
                    key={k}
                    onClick={() => {
                      setKind(k);
                      setCategory("");
                      setOffset(0);
                    }}
                  >
                    <UiText text={k === "equipment"
                      ? sw
                        ? "Vifaa"
                        : "Equipment"
                      : sw
                        ? "Wataalamu"
                        : "Professionals"} />
                  </button>
                ))}
              </div>
              <div className="grid gap-3 sm:grid-cols-2">
                <label className="field-label">
                  <UiText text={sw ? "Tafuta" : "Search"} />
                  <input
                    className="field-input mt-1"
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                  />
                </label>
                <label className="field-label">
                  <UiText text={sw ? "Kundi" : "Category"} />
                  <select
                    className="field-input mt-1"
                    value={category}
                    onChange={(e) => {
                      setCategory(e.target.value);
                      setOffset(0);
                    }}
                  >
                    <option value="">
                      <UiText text={sw ? "Makundi yote" : "All categories"} />
                    </option>
                    {kind === "equipment"
                      ? categories.map((c) => (
                          <option key={String(c.id)} value={String(c.id)}>
                            {String(sw ? c.name_sw : c.name_en)}
                          </option>
                        ))
                      : Object.keys(serviceKinds).map((k) => (
                          <option key={k} value={k}>
                            {serviceLabel(k, sw)}
                          </option>
                        ))}
                  </select>
                </label>
              </div>
              {catalogError ? (
                <div className="event-error" role="alert">
                  {catalogError}
                  <button
                    className="btn btn-outline mt-2"
                    type="button"
                    onClick={() => void load()}
                  >
                    <UiText text={sw ? "Jaribu tena" : "Retry"} />
                  </button>
                </div>
              ) : catalogBusy ? (
                <p className="p-6" role="status">
                  <UiText text={sw ? "Inapakia chaguo..." : "Loading options..."} />
                </p>
              ) : (
                <>
                  <div className="space-y-3">
                    {(kind === "equipment" ? equipment : services).map(
                      (item) => {
                        const id = String(
                          kind === "equipment" ? item.id : item.offering_id,
                        );
                        const choice = draft.choices.find(
                          (c) => c.id === id && c.kind === kind,
                        );
                        const available =
                          kind === "equipment"
                            ? Number(item.available_quantity) > 0
                            : item.is_available !== false;
                        return (
                          <article
                            className={`event-choice ${choice ? "is-selected" : ""}`}
                            key={id}
                          >
                            <EventCardImage
                              compact
                              media={item.media_paths ?? item.portfolio_media}
                              title={String(item.name ?? item.title)}
                            />
                            <div className="min-w-0 flex-1">
                              <label className="flex items-start gap-2">
                                <input
                                  type="checkbox"
                                  checked={!!choice}
                                  disabled={!available && !choice}
                                  onChange={() => toggle(item)}
                                />
                                <span className="event-title">
                                  {String(item.name ?? item.title)}
                                </span>
                              </label>
                              <p className="mt-2 text-sm text-muted">
                                {String(
                                  item.public_location_label ??
                                    item.display_name ??
                                    "",
                                )}
                              </p>
                              <p className="mt-1 text-sm font-semibold">
                                {eventPrice(item, sw)}
                              </p>
                              <p className="mt-1 text-xs">
                                <UiText text={kind === "equipment"
                                  ? `${sw ? "Inayopatikana kwa tarehe hizi" : "Available for these dates"}: ${item.available_quantity}`
                                  : available
                                    ? sw
                                      ? "Inapatikana kwa tarehe hizi"
                                      : "Available for these dates"
                                    : sw
                                      ? "Haipatikani kwa tarehe hizi"
                                      : "Unavailable for these dates"} />
                              </p>
                              {kind === "equipment" ? (
                                <label className="mt-3 flex flex-wrap items-center gap-2 text-sm">
                                  <UiText text={sw ? "Idadi" : "Quantity"} />
                                  <input
                                    className="field-input !w-24"
                                    type="number"
                                    min="1"
                                    max={Number(item.available_quantity)}
                                    disabled={!choice}
                                    value={choice?.quantity ?? 1}
                                    onChange={(e) => {
                                      const quantity = Number(e.target.value);
                                      setDraft((old) => ({
                                        ...old,
                                        choices: old.choices.map((c) =>
                                          c.id === id && c.kind === kind
                                            ? { ...c, quantity }
                                            : c,
                                        ),
                                      }));
                                    }}
                                  />
                                </label>
                              ) : null}
                              <Link
                                href={`/events/${kind}/${id}`}
                                target="_blank"
                                rel="noopener"
                                className="mt-2 inline-block text-sm underline"
                              >
                                <UiText text={sw
                                  ? "Maelezo (kichupo kipya)"
                                  : "Details (new tab)"} />
                              </Link>
                            </div>
                          </article>
                        );
                      },
                    )}
                  </div>
                  {!(kind === "equipment" ? equipment : services).length ? (
                    <p className="surface-card p-6">
                      <UiText text={sw
                        ? "Hakuna matokeo. Badili kundi, eneo au maneno ya kutafuta."
                        : "No matching results. Change category, location or search words."} />
                    </p>
                  ) : null}
                  <div className="flex items-center justify-between gap-2">
                    <button
                      type="button"
                      className="btn btn-outline"
                      disabled={offset === 0}
                      onClick={() => setOffset((o) => Math.max(0, o - 30))}
                    >
                      <UiText text={sw ? "Iliyopita" : "Previous"} />
                    </button>
                    <span className="text-sm">
                      <UiText text={sw ? "Ukurasa" : "Page"} /> {offset / 30 + 1}
                    </span>
                    <button
                      type="button"
                      className="btn btn-outline"
                      disabled={!more}
                      onClick={() => setOffset((o) => o + 30)}
                    >
                      <UiText text={sw ? "Inayofuata" : "Next"} />
                    </button>
                  </div>
                </>
              )}
            </section>
          ) : null}
          {step === 2 ? (
            <section className="surface-card space-y-4 p-5">
              <h2 className="text-xl font-bold">
                <UiText text={sw ? "Kagua kabla ya kutuma" : "Review before sending"} />
              </h2>
              <p className="text-sm text-muted">
                <UiText text={sw
                  ? "Upatikanaji haujahifadhiwa bado. Mtoa huduma atathibitisha na kutuma quotation; hakuna malipo sasa."
                  : "Availability is not reserved yet. Providers will confirm and send a quotation; no payment is due now."} />
              </p>
              {draft.choices.map((c) => {
                const check = checks.find(
                  (x) => x.id === c.id && x.kind === c.kind,
                );
                return (
                  <div
                    className="border-t border-[#dce6df] pt-3"
                    key={`${c.kind}:${c.id}`}
                  >
                    <p className="event-title">
                      {c.name}
                      {c.kind === "equipment" ? ` x ${c.quantity}` : ""}
                    </p>
                    <p className="text-sm text-muted">{c.price}</p>
                    <p
                      className={`mt-1 text-sm ${checkedFor !== fingerprint ? "text-muted" : check?.is_available ? "text-green-800" : "text-red-800"}`}
                    >
                      <UiText text={checkedFor !== fingerprint
                        ? sw
                          ? "Kagua upatikanaji tena."
                          : "Recheck availability."
                        : check?.is_available
                          ? sw
                            ? "Inapatikana sasa; inasubiri uthibitisho."
                            : "Currently available; awaiting provider confirmation."
                          : sw
                            ? "Haipatikani kwa eneo, muda au idadi hii. Hariri au ondoa chaguo."
                            : "Unavailable for this location, time or quantity. Edit or remove this selection."} />
                    </p>
                  </div>
                );
              })}
              <button
                type="button"
                className="btn btn-outline"
                disabled={busy}
                onClick={() => void go(2)}
              >
                <UiText text={sw ? "Kagua upatikanaji tena" : "Recheck availability"} />
              </button>
            </section>
          ) : null}
          <div className="mt-6 flex flex-wrap gap-3">
            {step > 0 ? (
              <button
                type="button"
                className="btn btn-outline"
                disabled={busy}
                onClick={() => setStep(step - 1)}
              >
                <UiText text={sw ? "Rudi" : "Back"} />
              </button>
            ) : null}
            <button
              className="btn btn-success"
              disabled={busy || !ready || (step === 2 && blocked)}
            >
              <UiText text={busy
                ? sw
                  ? "Inachakata..."
                  : "Working..."
                : step === 2
                  ? sw
                    ? "Omba quotation ya tukio"
                    : "Request event quotation"
                  : sw
                    ? "Endelea"
                    : "Continue"} />
            </button>
          </div>
        </div>
        <aside className="event-summary surface-card rounded-2xl p-5">
          {summary}
        </aside>
      </form>
      <div className="event-mobile-summary">
        <span className="text-sm font-semibold">
          {draft.choices.length} <UiText text={sw ? "vimechaguliwa" : "selected"} />
        </span>
        <button
          className="btn btn-success"
          type="button"
          disabled={busy}
          onClick={() => void go(step === 2 ? 1 : step + 1)}
        >
          <UiText text={step === 2 ? (sw ? "Hariri" : "Edit") : sw ? "Endelea" : "Continue"} />
        </button>
      </div>
    </div>
  );
}
