import Link from "next/link";
import { cookies } from "next/headers";
import { BackNavButton } from "@/components/back-nav-button";
import { CategoryRouteSelect } from "@/components/category-route-select";
import { GoogleAdSlot } from "@/components/google-ad-slot";
import { LocationBanner } from "@/components/location-banner";
import { PageShell } from "@/components/page-shell";
import { PromotionStrip } from "@/components/promotion-strip";
import { PublicListingGrid } from "@/components/public-listing-grid";
import { fetchCategories, fetchCountryId, fetchLocations, fetchPromotions, fetchPublicListings } from "@/lib/supabase-public";

export const revalidate = 120;
const pageSize = 20;

function buildPageHref(slug: string, params: Record<string, string | string[] | undefined>, nextPage: number) {
  const query = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (Array.isArray(value)) value.forEach((item) => query.append(key, item));
    else if (value) query.set(key, value);
  }
  if (nextPage <= 1) query.delete("page"); else query.set("page", String(nextPage));
  return query.size ? `/category/${slug}?${query}` : `/category/${slug}`;
}

export default async function CategoryPage({ params, searchParams }: { params: Promise<{ slug: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sw = (await cookies()).get("kodimali_language")?.value !== "en";
  const { slug } = await params;
  const query = await searchParams;
  const value = (key: string) => typeof query[key] === "string" ? query[key] as string : undefined;
  const currentPage = Math.max(1, Number.parseInt(value("page") ?? "1", 10) || 1);
  const regionId = value("regionId"); const districtId = value("districtId");
  const wardId = value("wardId"); const areaId = value("areaId");
  const latitude = Number(value("lat")); const longitude = Number(value("lng"));
  const searchText = value("q")?.trim();
  const parsedMinPrice = Number(value("minPrice")); const parsedMaxPrice = Number(value("maxPrice"));
  const minPrice = value("minPrice") && Number.isFinite(parsedMinPrice) ? parsedMinPrice : undefined;
  const maxPrice = value("maxPrice") && Number.isFinite(parsedMaxPrice) ? parsedMaxPrice : undefined;
  const pricePeriod = value("pricePeriod");
  const requestedSort = value("sort") ?? "recommended";
  const sort = (["recommended", "newest", "price_low", "price_high"] as const).includes(requestedSort as never) ? requestedSort as "recommended" | "newest" | "price_low" | "price_high" : "recommended";
  const countryId = await fetchCountryId();
  const [categories, listings, promotions, regions] = await Promise.all([
    fetchCategories(),
    fetchPublicListings({ categorySlug: slug, searchText, regionId, districtId, wardId, areaId, limit: pageSize, page: currentPage - 1, latitude: Number.isFinite(latitude) ? latitude : undefined, longitude: Number.isFinite(longitude) ? longitude : undefined, sessionSeed: slug, minPrice, maxPrice, pricePeriod, sort }),
    fetchPromotions({ surface: "website", placement: "category_page", limit: 1 }),
    countryId ? fetchLocations({ locationType: "region", parentId: countryId }) : Promise.resolve([]),
  ]);
  const category = categories.find((item: { slug: string }) => item.slug === slug);
  const totalCount = Number(listings[0]?.total_count ?? listings.length);
  const hasLocation = Boolean(regionId || districtId || wardId || areaId);

  return <PageShell className="pb-20">
    <section className="category-browser-head">
      <div className="category-title-row">
        <BackNavButton fallbackHref="/" label={sw ? "Nyuma" : "Back"} />
        <div className="min-w-0 flex-1"><h1>{category?.name ?? slug}</h1><p>{sw ? `${totalCount} zimepatikana` : `${totalCount} available`}</p></div>
        <CategoryRouteSelect categories={categories as Array<{ id: string; slug: string; name: string }>} value={slug} label={sw ? "Badili aina" : "Change category"} />
      </div>
      <form action={`/category/${slug}`} className="category-filter-form">
        {(["regionId", "districtId", "wardId", "areaId", "lat", "lng"] as const).map((name) => value(name) ? <input key={name} type="hidden" name={name} value={value(name)} /> : null)}
        <div className="category-inline-search"><svg aria-hidden="true" viewBox="0 0 24 24" fill="none"><circle cx="11" cy="11" r="6.5" stroke="currentColor" strokeWidth="2"/><path d="m16 16 4 4" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/></svg><input name="q" defaultValue={searchText} placeholder={sw ? `Tafuta ${category?.name ?? slug}` : `Search ${category?.name ?? slug}`} /><button>{sw ? "Tafuta" : "Search"}</button></div>
        <div className="category-browser-controls">
          <details className="category-location-filter"><summary>{hasLocation ? (sw ? "Eneo limechaguliwa" : "Location selected") : (sw ? "Eneo lote" : "Any location")}</summary><div className="category-location-panel"><LocationBanner visibleByDefault persistent regions={regions.map((item: { id: string; name: string }) => ({ id: item.id, name: item.name }))} /></div></details>
          <details className="category-price-filter"><summary>{sw ? "Bei" : "Price"}</summary><div className="category-price-panel"><label>{sw ? "Bei ya chini" : "Minimum"}<input name="minPrice" type="number" min="0" defaultValue={minPrice ?? ""} /></label><label>{sw ? "Bei ya juu" : "Maximum"}<input name="maxPrice" type="number" min="0" defaultValue={maxPrice ?? ""} /></label><select name="pricePeriod" defaultValue={pricePeriod ?? ""} aria-label={sw ? "Kipindi cha bei" : "Price period"}><option value="">{sw ? "Kipindi chochote" : "Any period"}</option><option value="hour">{sw ? "Kwa saa" : "Per hour"}</option><option value="day">{sw ? "Kwa siku" : "Per day"}</option><option value="week">{sw ? "Kwa wiki" : "Per week"}</option><option value="month">{sw ? "Kwa mwezi" : "Per month"}</option><option value="year">{sw ? "Kwa mwaka" : "Per year"}</option></select></div></details>
          <label className="category-sort-control"><span>{sw ? "Panga kwa" : "Sort"}</span><select name="sort" defaultValue={sort}><option value="recommended">{sw ? "Zilizopendekezwa" : "Recommended"}</option><option value="newest">{sw ? "Mpya kwanza" : "Newest"}</option><option value="price_low">{sw ? "Bei ndogo" : "Lowest price"}</option><option value="price_high">{sw ? "Bei kubwa" : "Highest price"}</option></select></label>
          <button className="category-apply-button">{sw ? "Tumia" : "Apply"}</button>
        </div>
      </form>
    </section>
    <PromotionStrip promotions={promotions as never} />
    <PublicListingGrid listings={listings as Array<{ listing_id: string }>} adSlot="category" clientId={process.env.ADSENSE_CLIENT_ID ?? ""} slotId={process.env.ADSENSE_SLOT_CATEGORY ?? ""} />
    <section className="mt-8 flex flex-wrap items-center justify-between gap-3"><p className="section-copy text-sm">{sw ? "Ukurasa" : "Page"} {currentPage}</p><div className="flex flex-wrap gap-3">{currentPage > 1 ? <Link href={buildPageHref(slug, query, currentPage - 1)} className="btn btn-outline">{sw ? "Iliyopita" : "Previous"}</Link> : null}{listings.length === pageSize ? <Link href={buildPageHref(slug, query, currentPage + 1)} className="btn btn-primary">{sw ? "Inayofuata" : "Next"}</Link> : null}</div></section>
    <GoogleAdSlot slot="category" clientId={process.env.ADSENSE_CLIENT_ID ?? ""} slotId={process.env.ADSENSE_SLOT_CATEGORY ?? ""} />
  </PageShell>;
}
