"use client";

import Link from "next/link";
import Image from "next/image";
import { FormEvent, useCallback, useEffect, useState } from "react";
import { getBrowserSupabase } from "@/lib/supabase-browser";
import { useLanguage } from "@/components/language-provider";
import { EventLocationFields } from "@/components/event-location-fields";

type Row = Record<string, unknown>;
const pageSize = 12;

export function EventsPublicCatalog() {
  const { language } = useLanguage();
  const sw = language === "sw";
  const supabase = getBrowserSupabase();
  const [mode, setMode] = useState<"equipment" | "service">("equipment");
  const [rows, setRows] = useState<Row[]>([]);
  const [categories, setCategories] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const [filters, setFilters] = useState({
    search: "",
    category: "",
    location: "",
    kind: "",
    min: "",
    max: "",
    start: "",
    end: "",
    sort: "recommended",
  });
  const load = useCallback(
    async (reset = true) => {
      setLoading(true);
      const offset = reset ? 0 : rows.length;
      const params =
        mode === "equipment"
          ? {
              p_search: filters.search || null,
              p_category_id: filters.category || null,
              p_location_id: filters.location || null,
              p_start_at: filters.start
                ? new Date(filters.start).toISOString()
                : null,
              p_end_at: filters.end
                ? new Date(filters.end).toISOString()
                : null,
              p_min_price: Number(filters.min) || null,
              p_max_price: Number(filters.max) || null,
              p_sort: filters.sort,
              p_limit: pageSize,
              p_offset: offset,
            }
          : {
              p_search: filters.search || null,
              p_provider_kind: filters.kind || null,
              p_location_id: filters.location || null,
              p_start_at: filters.start
                ? new Date(filters.start).toISOString()
                : null,
              p_end_at: filters.end
                ? new Date(filters.end).toISOString()
                : null,
              p_min_price: Number(filters.min) || null,
              p_max_price: Number(filters.max) || null,
              p_sort: filters.sort,
              p_limit: pageSize,
              p_offset: offset,
            };
      const { data, error } = await supabase.rpc(
        mode === "equipment"
          ? "search_public_event_equipment"
          : "search_public_event_services",
        params as never,
      );
      setLoading(false);
      if (error) {
        setRows([]);
        return;
      }
      const next = (data ?? []) as Row[];
      setRows(reset ? next : [...rows, ...next]);
    },
    [filters, mode, rows, supabase],
  );
  useEffect(() => {
    void Promise.all([
      supabase
        .from("event_equipment_categories")
        .select("id,name_sw,name_en")
        .eq("is_active", true)
        .order("display_order"),
    ]).then(([categoryResult]) => {
      setCategories((categoryResult.data ?? []) as Row[]);
    });
  }, [supabase]);
  useEffect(() => {
    void load(true);
  }, [mode]); // eslint-disable-line react-hooks/exhaustive-deps
  function submit(event: FormEvent) {
    event.preventDefault();
    void load(true);
  }
  return (
    <section id="individual-marketplace">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="eyebrow">
            {sw ? "Vifaa na Huduma" : "Equipment and services"}
          </p>
          <h2 className="mt-3 font-heading text-3xl font-semibold">
            {sw
              ? "Kodisha kitu kimoja bila kuunda package"
              : "Book one item without building a package"}
          </h2>
        </div>
        <a className="btn btn-outline" href="#plan-event">
          {sw ? "Au panga tukio kamili" : "Or plan a complete event"}
        </a>
      </div>
      <div className="mt-6 flex gap-2">
        <button
          className={`btn ${mode === "equipment" ? "btn-success" : "btn-outline"}`}
          onClick={() => setMode("equipment")}
        >
          {sw ? "Vifaa" : "Equipment"}
        </button>
        <button
          className={`btn ${mode === "service" ? "btn-success" : "btn-outline"}`}
          onClick={() => setMode("service")}
        >
          {sw ? "Wataalamu" : "Professionals"}
        </button>
      </div>
      <form
        className="soft-panel mt-5 grid gap-3 p-4 sm:grid-cols-2 lg:grid-cols-4"
        onSubmit={submit}
      >
        <input
          className="field-input"
          placeholder={
            sw ? "Tafuta jina au maelezo" : "Search name or description"
          }
          value={filters.search}
          onChange={(e) => setFilters({ ...filters, search: e.target.value })}
        />
        {mode === "equipment" ? (
          <select
            className="field-input"
            value={filters.category}
            onChange={(e) =>
              setFilters({ ...filters, category: e.target.value })
            }
          >
            <option value="">{sw ? "Vifaa vyote" : "All equipment"}</option>
            {categories.map((row) => (
              <option value={String(row.id)} key={String(row.id)}>
                {String(sw ? row.name_sw : row.name_en)}
              </option>
            ))}
          </select>
        ) : (
          <select
            className="field-input"
            value={filters.kind}
            onChange={(e) => setFilters({ ...filters, kind: e.target.value })}
          >
            <option value="">
              {sw ? "Wataalamu wote" : "All professionals"}
            </option>
            {[
              "mc_host",
              "dj",
              "photographer",
              "videographer",
              "planner",
              "decorator",
              "caterer",
              "performer",
              "transport_delivery",
            ].map((kind) => (
              <option value={kind} key={kind}>
                {kind.replaceAll("_", " ")}
              </option>
            ))}
          </select>
        )}
        <div className="sm:col-span-2 lg:col-span-4">
          <EventLocationFields
            value={filters.location}
            onChange={(location) =>
              setFilters((current) => ({ ...current, location }))
            }
          />
        </div>
        <input
          className="field-input"
          type="datetime-local"
          value={filters.start}
          onChange={(e) => setFilters({ ...filters, start: e.target.value })}
        />
        <input
          className="field-input"
          type="datetime-local"
          value={filters.end}
          onChange={(e) => setFilters({ ...filters, end: e.target.value })}
        />
        <input
          className="field-input"
          type="number"
          min="0"
          placeholder={sw ? "Bei ya chini" : "Minimum price"}
          value={filters.min}
          onChange={(e) => setFilters({ ...filters, min: e.target.value })}
        />
        <input
          className="field-input"
          type="number"
          min="0"
          placeholder={sw ? "Bei ya juu" : "Maximum price"}
          value={filters.max}
          onChange={(e) => setFilters({ ...filters, max: e.target.value })}
        />
        <select
          className="field-input"
          value={filters.sort}
          onChange={(e) => setFilters({ ...filters, sort: e.target.value })}
        >
          <option value="recommended">
            {sw ? "Zilizopendekezwa" : "Recommended"}
          </option>
          <option value="newest">{sw ? "Mpya" : "Newest"}</option>
          <option value="price_low">
            {sw ? "Bei ndogo kwanza" : "Lowest price"}
          </option>
          <option value="price_high">
            {sw ? "Bei kubwa kwanza" : "Highest price"}
          </option>
        </select>
        <button className="btn btn-success">{sw ? "Tafuta" : "Search"}</button>
      </form>
      {loading ? (
        <p className="mt-6 text-muted">{sw ? "Inapakia…" : "Loading…"}</p>
      ) : rows.length === 0 ? (
        <p className="mt-6 text-muted">
          {sw ? "Hakuna kilichopatikana." : "Nothing found."}
        </p>
      ) : (
        <div className="mt-6 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {rows.map((row) => (
            <Link
              className="group surface-card overflow-hidden p-5 transition hover:-translate-y-1"
              href={
                mode === "equipment"
                  ? `/events/equipment/${String(row.id)}`
                  : `/events/service/${String(row.offering_id)}`
              }
              key={String(row.id ?? row.offering_id)}
            >
              <CatalogMedia
                media={row.media_paths ?? row.portfolio_media}
                title={String(row.name ?? row.title)}
              />
              <p className="text-xs font-bold uppercase tracking-wider text-brand-teal">
                {mode === "equipment"
                  ? String(sw ? row.category_name_sw : row.category_name_en)
                  : String(row.provider_kind).replaceAll("_", " ")}
              </p>
              <h3 className="mt-2 font-heading text-xl font-semibold">
                {String(row.name ?? row.title)}
              </h3>
              <p className="mt-2 text-sm text-muted">
                {String(row.public_location_label ?? row.display_name ?? "")}
              </p>
              <p className="mt-4 font-bold">
                {row.price_amount_tzs == null
                  ? sw
                    ? "Omba quotation"
                    : "Request quote"
                  : `TZS ${Number(row.price_amount_tzs).toLocaleString()}`}
              </p>
              {row.available_quantity != null ? (
                <p className="mt-1 text-sm text-muted">
                  {sw ? "Vilivyopo" : "Available"}:{" "}
                  {String(row.available_quantity)}
                </p>
              ) : row.is_available === false ? (
                <p className="mt-1 text-sm font-semibold text-red-700">
                  {sw ? "Ratiba imejaa" : "Unavailable for selected time"}
                </p>
              ) : null}
            </Link>
          ))}
        </div>
      )}
      {rows.length >= pageSize ? (
        <button
          className="btn btn-outline mt-6"
          disabled={loading}
          onClick={() => void load(false)}
        >
          {sw ? "Onyesha zaidi" : "Load more"}
        </button>
      ) : null}
    </section>
  );
}

function CatalogMedia({ media, title }: { media: unknown; title: string }) {
  const supabase = getBrowserSupabase();
  const path =
    Array.isArray(media) && typeof media[0] === "string" ? media[0] : "";
  const [src, setSrc] = useState(path.startsWith("http") ? path : "");
  useEffect(() => {
    let active = true;
    if (!path || path.startsWith("http")) return;
    void supabase.storage
      .from("listing-media")
      .createSignedUrl(path, 3600)
      .then(({ data }) => {
        if (active) setSrc(data?.signedUrl ?? "");
      });
    return () => {
      active = false;
    };
  }, [path, supabase]);
  return (
    <div className="relative mb-4 aspect-[4/3] overflow-hidden rounded-2xl bg-[linear-gradient(145deg,#dfece5,#b9d8d0)]">
      {src ? (
        <Image
          src={src}
          alt={title}
          fill
          sizes="(max-width: 640px) 100vw, 33vw"
          className="object-cover transition duration-700 group-hover:scale-[1.03]"
        />
      ) : null}
    </div>
  );
}
