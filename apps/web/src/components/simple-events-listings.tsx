"use client";
import { PromotionCard, PromotionStrip, type Promotion } from "@/components/promotion-strip";
import { LISTINGS_PER_SPONSORED_CARD, sponsoredLayout } from "@/lib/sponsored-layout";
import { UiDiv, UiInput, UiNav, UiSelect, UiText } from "@/components/ui-text";

import { EventCardImage } from "@/components/event-card-image";
import { eventPrice, serviceKinds, serviceLabel } from "@/lib/event-display";
import Link from "next/link";
import { Fragment, useCallback, useEffect, useRef, useState } from "react";
import { EventLocationFields } from "@/components/event-location-fields";
import { useLanguage } from "@/components/language-provider";
import { getBrowserSupabase } from "@/lib/supabase-browser";

type Row = Record<string, unknown>;

export function SimpleEventsListings({ initialRows, initialCategories, initialMode = "equipment", initialPromotions = [] }: { initialPromotions?: Promotion[]; initialRows?: Row[]; initialCategories?: Row[]; initialMode?: "equipment" | "service" }) {
  const { language } = useLanguage();
  const sw = language === "sw";
  const supabase = getBrowserSupabase();
  const [mode, setMode] = useState<"equipment" | "service">(initialMode);
  const [locationId, setLocationId] = useState("");
  const [promotions,setPromotions]=useState(initialPromotions);
  useEffect(()=>{const controller=new AbortController();void fetch(`/api/promotions?locationId=${encodeURIComponent(locationId)}`,{signal:controller.signal}).then(response=>response.ok?response.json():[]).then(rows=>{if(!controller.signal.aborted)setPromotions(rows);}).catch(()=>{if(!controller.signal.aborted)setPromotions([]);});return()=>controller.abort();},[locationId]);
  const [categoryId, setCategoryId] = useState("");
  const [providerKind, setProviderKind] = useState("");
  const [locationLabel, setLocationLabel] = useState("");
  const [locationKey, setLocationKey] = useState(0);
  const [categories, setCategories] = useState<Row[]>(initialCategories ?? []);
  const [rows, setRows] = useState<Row[]>(initialRows?.slice(0, 30) ?? []);
  const [loading, setLoading] = useState(initialRows === undefined);
  const [error, setError] = useState("");
  const [page, setPage] = useState(0);
  const [hasMore, setHasMore] = useState((initialRows?.length ?? 0) > 30);
  const [search, setSearch] = useState("");
  const [minPrice, setMinPrice] = useState("");
  const [maxPrice, setMaxPrice] = useState("");
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");
  const [sort, setSort] = useState("recommended");
  const [filters, setFilters] = useState({
    search: "",
    minPrice: "",
    maxPrice: "",
    start: "",
    end: "",
    sort: "recommended",
  });
  const requestId = useRef(0);
  // Every filter applies automatically; text inputs are debounced to keep browsing light.
  useEffect(() => {
    const timer = setTimeout(() => {
      setPage(0);
      setFilters({ search, minPrice, maxPrice, start, end, sort });
    }, 350);
    return () => clearTimeout(timer);
  }, [search, minPrice, maxPrice, start, end, sort]);
  function clearFilters() {
    setSearch("");
    setMinPrice("");
    setMaxPrice("");
    setStart("");
    setEnd("");
    setSort("recommended");
    setLocationId("");
    setLocationLabel("");
    setLocationKey((k) => k + 1);
    setCategoryId("");
    setProviderKind("");
    setPage(0);
    setFilters({
      search: "",
      minPrice: "",
      maxPrice: "",
      start: "",
      end: "",
      sort: "recommended",
    });
  }

  const load = useCallback(async () => {
    const request = ++requestId.current;
    if (!(initialRows && page === 0 && mode === initialMode && !categoryId && !providerKind && !locationId && !filters.search && !filters.minPrice && !filters.maxPrice && !filters.start && !filters.end && filters.sort === "recommended")) setLoading(true);
    setError("");
    try {
      const from = filters.start ? new Date(filters.start) : null;
      const to = filters.end ? new Date(filters.end) : null;
      if (
        (filters.minPrice && Number(filters.minPrice) < 0) ||
        (filters.maxPrice && Number(filters.maxPrice) < 0) ||
        (filters.minPrice &&
          filters.maxPrice &&
          Number(filters.minPrice) > Number(filters.maxPrice))
      )
        throw new Error(
          sw
            ? "Bei ya juu iwe sawa au kubwa kuliko bei ya chini."
            : "Maximum price must be at least the minimum price.",
        );
      if (
        Boolean(from) !== Boolean(to) ||
        (from &&
          to &&
          (to <= from ||
            !Number.isFinite(from.getTime()) ||
            !Number.isFinite(to.getTime())))
      )
        throw new Error(
          sw
            ? "Chagua mwanzo na mwisho sahihi."
            : "Select a valid start and end together.",
        );
      const params = {
        p_search: filters.search.trim() || null,
        ...(mode === "equipment"
          ? { p_category_id: categoryId || null }
          : { p_provider_kind: providerKind || null }),
        p_location_id: locationId || null,
        p_start_at: from?.toISOString() ?? null,
        p_end_at: to?.toISOString() ?? null,
        p_min_price: filters.minPrice.trim() ? Number(filters.minPrice) : null,
        p_max_price: filters.maxPrice.trim() ? Number(filters.maxPrice) : null,
        p_sort: filters.sort,
        p_limit: 31,
        p_offset: page * 30,
      };
      const { data, error: failure } = await supabase.rpc(
        mode === "equipment"
          ? "search_public_event_equipment"
          : "search_public_event_services",
        params as never,
      );
      if (failure) throw failure;
      if (request !== requestId.current) return;
      const result = (data ?? []) as Row[];
      setRows(result.slice(0, 30));
      setHasMore(result.length > 30);
    } catch (failure) {
      if (request === requestId.current)
        setError(String((failure as Row)?.message ?? failure));
    } finally {
      if (request === requestId.current) setLoading(false);
    }
  }, [categoryId, providerKind, locationId, mode, page, filters, supabase, sw, initialRows, initialMode]);
  useEffect(() => {
    const requestRef = requestId;
    const task = window.setTimeout(() => { void load(); }, 0);
    return () => {
      window.clearTimeout(task);
      requestRef.current++;
    };
  }, [load]);
  useEffect(() => {
    let active = true;
    void supabase
      .from("event_equipment_categories")
      .select("id,name_sw,name_en")
      .eq("is_active", true)
      .order("display_order")
      .then(({ data, error: failure }) => {
        if (!active) return;
        if (failure) setError(failure.message);
        else setCategories((data ?? []) as Row[]);
      });
    return () => {
      active = false;
    };
  }, [supabase]);
  const adLayout = sponsoredLayout(promotions, rows.length);
  return (
    <div className="events-ui space-y-4 pb-16" id="individual-marketplace">
      <header className="event-intro">
        <h1>
          <UiText text={sw
            ? "Vifaa na wataalamu wa matukio"
            : "Event equipment and professionals"} />
        </h1>
        <p>
          <UiText text={sw
            ? "Tafuta unachohitaji, au panga tukio na uombe quotation."
            : "Find what you need, or plan an event and request a quotation."} />
        </p>
      </header>
      <section>
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="grid grid-cols-2 gap-2">
            <button
              className={`btn ${mode === "equipment" ? "btn-success" : "btn-outline"}`}
              onClick={() => {
                setMode("equipment");
                setPage(0);
              }}
            >
              <UiText text={sw ? "Vifaa" : "Equipment"} />
            </button>
            <button
              className={`btn ${mode === "service" ? "btn-success" : "btn-outline"}`}
              onClick={() => {
                setMode("service");
                setPage(0);
                setCategoryId("");
              }}
            >
              <UiText text={sw ? "Wataalamu" : "Professionals"} />
            </button>
          </div>
          <Link href="/events/plan" className="btn btn-success">
            <UiText text={sw ? "Panga Tukio" : "Plan event"} />
          </Link>
        </div>
        {mode === "equipment" ? (
          <div className="event-category-rail mt-4 flex gap-3 overflow-x-auto pb-2">
            <button
              className={`event-category-tile ${categoryId === "" ? "is-active" : ""}`}
              onClick={() => {
                setCategoryId("");
                setPage(0);
              }}
              type="button"
            >
              <UiText text={sw ? "Vifaa vyote" : "All equipment"} />
            </button>
            {categories.map((category) => (
              <button
                className={`event-category-tile ${categoryId === String(category.id) ? "is-active" : ""}`}
                key={String(category.id)}
                onClick={() => {
                  setCategoryId(String(category.id));
                  setPage(0);
                }}
                type="button"
              >
                <UiText text={String(sw ? category.name_sw : category.name_en)} />
              </button>
            ))}
          </div>
        ) : null}
        <div className="mt-4 grid gap-3 sm:grid-cols-[minmax(0,1fr)_220px]">
          <label className="field-label">
            <UiText text={sw ? "Tafuta vifaa au huduma" : "Search equipment or services"} />
            <UiInput
              className="field-input mt-1"
              value={search}
              placeholder={
                sw
                  ? "Mfano: viti, mapambo..."
                  : "For example: chairs, decoration..."
              }
              onChange={(e) => setSearch(e.target.value)}
            />
          </label>
          <label className="field-label">
            <UiText text={sw ? "Panga matokeo" : "Sort results"} />
            <select
              className="field-input mt-1"
              value={sort}
              onChange={(e) => setSort(e.target.value)}
            >
              <option value="recommended">
                <UiText text={sw ? "Zilizopendekezwa" : "Recommended"} />
              </option>
              <option value="newest"><UiText text={sw ? "Mpya" : "Newest"} /></option>
              <option value="price_low">
                <UiText text={sw ? "Bei ndogo kwanza" : "Lowest price"} />
              </option>
              <option value="price_high">
                <UiText text={sw ? "Bei kubwa kwanza" : "Highest price"} />
              </option>
            </select>
          </label>
        </div>
        {mode === "service" ? (
          <label className="field-label mt-3 block max-w-md">
            <UiText text={sw ? "Aina ya huduma" : "Service category"} />
            <UiSelect
              aria-label={sw ? "Aina ya huduma" : "Service category"}
              className="field-input mt-1"
              value={providerKind}
              onChange={(e) => {
                setProviderKind(e.target.value);
                setPage(0);
              }}
            >
              <option value=""><UiText text={sw ? "Huduma zote" : "All services"} /></option>
              {Object.keys(serviceKinds).map((k) => (
                <option key={k} value={k}>
                  {serviceLabel(k, sw)}
                </option>
              ))}
            </UiSelect>
          </label>
        ) : null}
        <details className="surface-card mt-4 p-4">
          <summary className="cursor-pointer font-semibold">
            <UiText text={sw
              ? "Vichujio: eneo, bei na tarehe"
              : "Filters: location, price and dates"} />
          </summary>
          <div className="mt-4">
            <EventLocationFields
              key={locationKey}
              value={locationId}
              onLabelChange={setLocationLabel}
              onChange={(value) => {
                setLocationId(value);
                setPage(0);
              }}
            />
          </div>
          <div className="mt-4 grid gap-3 sm:grid-cols-2">
            <label className="field-label">
              <UiText text={sw ? "Bei ya chini (TZS)" : "Minimum price (TZS)"} />
              <input
                className="field-input mt-1"
                type="number"
                min="0"
                value={minPrice}
                onChange={(e) => setMinPrice(e.target.value)}
              />
            </label>
            <label className="field-label">
              <UiText text={sw ? "Bei ya juu (TZS)" : "Maximum price (TZS)"} />
              <input
                className="field-input mt-1"
                type="number"
                min="0"
                value={maxPrice}
                onChange={(e) => setMaxPrice(e.target.value)}
              />
            </label>
            <label className="field-label">
              <UiText text={sw ? "Tarehe na saa ya kuanza" : "Start date and time"} />
              <input
                className="field-input mt-1"
                type="datetime-local"
                value={start}
                onChange={(e) => setStart(e.target.value)}
              />
            </label>
            <label className="field-label">
              <UiText text={sw ? "Tarehe na saa ya kumaliza" : "End date and time"} />
              <input
                className="field-input mt-1"
                type="datetime-local"
                value={end}
                onChange={(e) => setEnd(e.target.value)}
              />
            </label>
          </div>
          <p className="mt-3 text-sm text-muted">
            <UiText text={sw
              ? "Vichujio hutumika moja kwa moja. Bei zinaweza kuwa na vipimo tofauti; angalia kila tangazo."
              : "Filters apply automatically. Pricing units can differ; check each listing."} />
          </p>
        </details>
        <UiDiv
          className="mt-3 flex flex-wrap items-center gap-2"
          aria-label={sw ? "Vichujio vilivyochaguliwa" : "Active filters"}
        >
          {locationId ? (
            <button
              className="event-chip"
              onClick={() => {
                setLocationId("");
                setLocationLabel("");
                setLocationKey((k) => k + 1);
                setPage(0);
              }}
            >
              {locationLabel ||
                (sw ? "Eneo limechaguliwa" : "Location selected")}{" "}
              <span aria-hidden="true">&times;</span>
            </button>
          ) : (
            <span className="text-sm text-muted">
              <UiText text={sw ? "Maeneo yote" : "All locations"} />
            </span>
          )}
          {categoryId ? (
            <button
              className="event-chip"
              onClick={() => {
                setCategoryId("");
                setPage(0);
              }}
            >
              {String(
                categories.find((c) => c.id === categoryId)?.[
                  sw ? "name_sw" : "name_en"
                ] ?? (sw ? "Kundi" : "Category"),
              )}{" "}
              <span aria-hidden="true">&times;</span>
            </button>
          ) : null}
          {providerKind ? (
            <button
              className="event-chip"
              onClick={() => {
                setProviderKind("");
                setPage(0);
              }}
            >
              {serviceLabel(providerKind, sw)}{" "}
              <span aria-hidden="true">&times;</span>
            </button>
          ) : null}
          {search ? (
            <button className="event-chip" onClick={() => setSearch("")}>
              {search} <span aria-hidden="true">&times;</span>
            </button>
          ) : null}
          {minPrice || maxPrice ? (
            <button
              className="event-chip"
              onClick={() => {
                setMinPrice("");
                setMaxPrice("");
              }}
            >
              TZS {minPrice || "0"} - {maxPrice || "..."}{" "}
              <span aria-hidden="true">&times;</span>
            </button>
          ) : null}
          {start || end ? (
            <button
              className="event-chip"
              onClick={() => {
                setStart("");
                setEnd("");
              }}
            >
              <UiText text={sw ? "Tarehe" : "Dates"} /> <span aria-hidden="true">&times;</span>
            </button>
          ) : null}
          <button
            className="ml-auto text-sm font-semibold underline"
            onClick={clearFilters}
          >
            <UiText text={sw ? "Ondoa vichujio" : "Clear filters"} />
          </button>
        </UiDiv>
        {!filters.start ? (
          <p className="mt-3 text-sm text-muted">
            <UiText text={sw
              ? "Chagua tarehe kuangalia upatikanaji. Idadi inayoonyeshwa ni jumla ya vifaa."
              : "Choose dates to check availability. Quantity shown without dates is total inventory."} />
          </p>
        ) : null}
        {error ? (
          <div className="event-error mt-6" role="alert">
            <p><UiText text={error} /></p>
            <button
              className="btn btn-outline mt-3"
              onClick={() => void load()}
            >
              <UiText text={sw ? "Jaribu tena" : "Retry"} />
            </button>
          </div>
        ) : loading ? (
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
              <UiText text={sw ? "Hakuna tangazo lililopatikana" : "No listing found"} />
            </h2>
            <p className="mt-2 text-sm text-muted">
              <UiText text={sw
                ? "Ondoa vichujio, badili eneo, au tuombe tukusaidie kupata mbadala."
                : "Clear filters, change location, or ask us to help find an alternative."} />
            </p>
            <div className="mt-5 flex flex-wrap justify-center gap-3">
              <button
                className="btn btn-outline"
                type="button"
                onClick={clearFilters}
              >
                <UiText text={sw ? "Ondoa vichujio" : "Clear filters"} />
              </button>
              <Link className="btn btn-success" href="/events/plan">
                <UiText text={sw ? "Nisaidie kupata mbadala" : "Help me find an alternative"} />
              </Link>
            </div>
          </div>
        ) : (
          <div className="mt-6 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
            {rows.map((row, index) => (
              <Fragment key={String(row.id ?? row.offering_id)}>
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
                      : serviceLabel(row.provider_kind, sw)}
                  </p>
                  <h2 className="event-title mt-2 text-lg">
                    {String(row.name ?? row.title)}
                  </h2>
                  <p className="mt-2 text-sm text-muted">
                    {String(
                      row.public_location_label ?? row.display_name ?? "",
                    )}
                  </p>
                  <p className="mt-4 font-bold">{eventPrice(row, sw)}</p>
                  <p className="mt-2 text-sm text-muted">
                    <UiText text={filters.start && filters.end
                      ? mode === "equipment"
                        ? `${sw ? "Idadi inayopatikana" : "Available quantity"}: ${row.available_quantity}`
                        : row.is_available === false
                          ? sw
                            ? "Haipatikani kwa tarehe hizi"
                            : "Unavailable for these dates"
                          : sw
                            ? "Inapatikana; inasubiri uthibitisho"
                            : "Available; confirmation required"
                      : sw
                        ? "Chagua tarehe kuangalia upatikanaji"
                        : "Choose dates to check availability"} />
                  </p>
                  <Link
                    className="btn btn-primary mt-4 w-full"
                    href={
                      mode === "equipment"
                        ? `/events/equipment/${row.id}`
                        : `/events/service/${row.offering_id}`
                    }
                  >
                    <UiText text={sw ? "Angalia maelezo" : "View details"} />
                  </Link>
                </div>
              </article>
              {(index + 1) % LISTINGS_PER_SPONSORED_CARD === 0 && adLayout.inline[Math.floor(index / LISTINGS_PER_SPONSORED_CARD)] && <PromotionCard key={adLayout.inline[Math.floor(index / LISTINGS_PER_SPONSORED_CARD)].promotion_id} promotion={adLayout.inline[Math.floor(index / LISTINGS_PER_SPONSORED_CARD)]} />}
              </Fragment>
            ))}
          </div>
        )}
        {!loading && !error ? (
          <UiNav
            className="mt-6 flex items-center justify-between"
            aria-label={sw ? "Kurasa" : "Pagination"}
          >
            <button
              className="btn btn-outline"
              disabled={page === 0}
              onClick={() => setPage((value) => value - 1)}
            >
              <UiText text={sw ? "Iliyopita" : "Previous"} />
            </button>
            <span>
              <UiText text={sw ? "Ukurasa" : "Page"} /> {page + 1}
            </span>
            <button
              className="btn btn-outline"
              disabled={!hasMore}
              onClick={() => setPage((value) => value + 1)}
            >
              <UiText text={sw ? "Inayofuata" : "Next"} />
            </button>
          </UiNav>
        ) : null}
        <PromotionStrip promotions={loading || error ? promotions : adLayout.remaining} />
      </section>
    </div>
  );
}
