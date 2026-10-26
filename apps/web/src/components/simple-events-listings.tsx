"use client";

import Image from "next/image";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { EventLocationFields } from "@/components/event-location-fields";
import { useLanguage } from "@/components/language-provider";
import { getBrowserSupabase } from "@/lib/supabase-browser";

type Row = Record<string, unknown>;

export function SimpleEventsListings() {
  const { language } = useLanguage();
  const sw = language === "sw";
  const supabase = getBrowserSupabase();
  const [mode, setMode] = useState<"equipment" | "service">("equipment");
  const [locationId, setLocationId] = useState("");
  const [categoryId, setCategoryId] = useState("");
  const [categories, setCategories] = useState<Row[]>([]);
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const load = useCallback(async () => {
    setLoading(true);
    const params =
      mode === "equipment"
        ? {
            p_search: null,
            p_category_id: categoryId || null,
            p_location_id: locationId || null,
            p_start_at: null,
            p_end_at: null,
            p_min_price: null,
            p_max_price: null,
            p_sort: "recommended",
            p_limit: 30,
            p_offset: 0,
          }
        : {
            p_search: null,
            p_provider_kind: null,
            p_location_id: locationId || null,
            p_start_at: null,
            p_end_at: null,
            p_min_price: null,
            p_max_price: null,
            p_sort: "recommended",
            p_limit: 30,
            p_offset: 0,
          };
    const { data } = await supabase.rpc(
      mode === "equipment"
        ? "search_public_event_equipment"
        : "search_public_event_services",
      params as never,
    );
    setRows((data ?? []) as Row[]);
    setLoading(false);
  }, [categoryId, locationId, mode, supabase]);
  useEffect(() => {
    void load();
  }, [load]);
  useEffect(() => {
    void supabase
      .from("event_equipment_categories")
      .select("id,name_sw,name_en")
      .eq("is_active", true)
      .order("display_order")
      .then(({ data }) => setCategories((data ?? []) as Row[]));
  }, [supabase]);
  return (
    <div className="space-y-6 pb-16">
      <section className="owner-hero rounded-[26px] p-6 text-white sm:p-8">
        <p className="eyebrow !text-brand-amber">KODIMALI Events</p>
        <h1 className="mt-2 font-heading text-3xl font-semibold sm:text-4xl">
          {sw
            ? "Vifaa na wataalamu wa sherehe"
            : "Event equipment and professionals"}
        </h1>
        <p className="mt-3 max-w-2xl text-white/70">
          {sw
            ? "Chagua eneo ukitaka kuona matangazo ya sehemu fulani, au vinjari matangazo yote."
            : "Choose a location to narrow the results, or browse every listing."}
        </p>
      </section>
      <section>
        <div className="flex items-center justify-between gap-3">
          <div className="flex gap-2">
            <button
              className={`btn ${mode === "equipment" ? "btn-success" : "btn-outline"}`}
              onClick={() => setMode("equipment")}
            >
              {sw ? "Vifaa" : "Equipment"}
            </button>
            <button
              className={`btn ${mode === "service" ? "btn-success" : "btn-outline"}`}
              onClick={() => {
                setMode("service");
                setCategoryId("");
              }}
            >
              {sw ? "Wataalamu" : "Professionals"}
            </button>
          </div>
          <Link href="/events/plan" className="btn btn-outline">
            {sw ? "Panga Tukio" : "Plan event"}
          </Link>
        </div>
        {mode === "equipment" ? (
          <div className="event-category-rail mt-4 flex gap-3 overflow-x-auto pb-2">
            <button
              className={`event-category-tile ${categoryId === "" ? "is-active" : ""}`}
              onClick={() => setCategoryId("")}
              type="button"
            >
              {sw ? "Vifaa vyote" : "All equipment"}
            </button>
            {categories.map((category) => (
              <button
                className={`event-category-tile ${categoryId === String(category.id) ? "is-active" : ""}`}
                key={String(category.id)}
                onClick={() => setCategoryId(String(category.id))}
                type="button"
              >
                {String(sw ? category.name_sw : category.name_en)}
              </button>
            ))}
          </div>
        ) : null}
        <details className="surface-card mt-5 p-4 sm:p-5">
          <summary className="cursor-pointer text-sm font-bold">
            {sw
              ? "Chuja kwa eneo (si lazima)"
              : "Filter by location (optional)"}
          </summary>
          <div className="mt-4">
            <EventLocationFields value={locationId} onChange={setLocationId} />
          </div>
        </details>
        {loading ? (
          <div className="mt-6 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
            {[1, 2, 3].map((item) => (
              <div
                className="surface-card h-72 animate-pulse bg-brand-card-soft"
                key={item}
              />
            ))}
          </div>
        ) : rows.length === 0 ? (
          <div className="surface-card mt-6 p-8 text-center">
            <h2 className="font-heading text-xl font-semibold">
              {sw ? "Hakuna tangazo lililopatikana" : "No listing found"}
            </h2>
            <p className="mt-2 text-sm text-muted">
              {sw
                ? "Ondoa vichujio, badili eneo, au tuombe tukusaidie kupata mbadala."
                : "Clear filters, change location, or ask us to help find an alternative."}
            </p>
            <div className="mt-5 flex flex-wrap justify-center gap-3">
              <button
                className="btn btn-outline"
                type="button"
                onClick={() => {
                  setLocationId("");
                  setCategoryId("");
                }}
              >
                {sw ? "Ondoa vichujio" : "Clear filters"}
              </button>
              <Link className="btn btn-success" href="/events/plan">
                {sw ? "Nisaidie kupata mbadala" : "Help me find an alternative"}
              </Link>
            </div>
          </div>
        ) : (
          <div className="mt-6 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
            {rows.map((row) => (
              <article
                className="surface-card overflow-hidden"
                key={String(row.id ?? row.offering_id)}
              >
                <EventCardImage
                  media={row.media_paths ?? row.portfolio_media}
                  title={String(row.name ?? row.title)}
                />
                <div className="p-5">
                  <p className="text-xs font-bold uppercase tracking-wider text-brand-teal">
                    {mode === "equipment"
                      ? String(sw ? row.category_name_sw : row.category_name_en)
                      : String(row.provider_kind).replaceAll("_", " ")}
                  </p>
                  <h2 className="mt-2 font-heading text-xl font-semibold">
                    {String(row.name ?? row.title)}
                  </h2>
                  <p className="mt-2 text-sm text-muted">
                    {String(
                      row.public_location_label ?? row.display_name ?? "",
                    )}
                  </p>
                  <p className="mt-4 font-bold">
                    {row.price_amount_tzs == null
                      ? sw
                        ? "Omba quotation"
                        : "Request quote"
                      : `TZS ${Number(row.price_amount_tzs).toLocaleString()}`}
                  </p>
                  <Link
                    className="btn btn-primary mt-4 w-full"
                    href={
                      mode === "equipment"
                        ? `/events/equipment/${row.id}`
                        : `/events/service/${row.offering_id}`
                    }
                  >
                    {sw ? "Angalia maelezo" : "View details"}
                  </Link>
                </div>
              </article>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

function EventCardImage({ media, title }: { media: unknown; title: string }) {
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
    <div className="relative aspect-[4/3] bg-brand-card-soft">
      {src ? (
        <Image
          src={src}
          alt={title}
          fill
          sizes="(max-width:640px) 100vw,33vw"
          className="object-cover"
        />
      ) : (
        <div className="h-full bg-[linear-gradient(145deg,#dfece5,#b9d8d0)]" />
      )}
    </div>
  );
}
