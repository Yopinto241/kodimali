import { BackNavButton } from "@/components/back-nav-button";
import Link from "next/link";
import { cookies } from "next/headers";

import { GoogleAdSlot } from "@/components/google-ad-slot";
import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";
import { PromotionStrip } from "@/components/promotion-strip";
import { PublicListingGrid } from "@/components/public-listing-grid";
import { SaveSearchButton } from "@/components/save-search-button";
import {
  fetchCategories,
  fetchPromotions,
  fetchPublicListings,
  fetchActiveFeaturedListingIds,
} from "@/lib/supabase-public";

export const revalidate = 15;

const pageSize = 20;

function buildPageHref(
  params: Record<string, string | string[] | undefined>,
  nextPage: number,
) {
  const query = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (Array.isArray(value)) {
      for (const item of value) {
        query.append(key, item);
      }
      continue;
    }
    if (value) {
      query.set(key, value);
    }
  }
  if (nextPage <= 1) {
    query.delete("page");
  } else {
    query.set("page", String(nextPage));
  }
  const serialized = query.toString();
  return serialized ? `/listings?${serialized}` : "/listings";
}

export default async function ListingsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sw = (await cookies()).get("kodimali_language")?.value !== "en";
  const params = await searchParams;
  const adsenseClientId = process.env.ADSENSE_CLIENT_ID ?? "";
  const adsenseHomeSlot = process.env.ADSENSE_SLOT_HOME ?? "";
  const currentPage = Math.max(
    1,
    typeof params.page === "string" ? Number.parseInt(params.page, 10) || 1 : 1,
  );
  const regionId =
    typeof params.regionId === "string" ? params.regionId : undefined;
  const districtId =
    typeof params.districtId === "string" ? params.districtId : undefined;
  const wardId = typeof params.wardId === "string" ? params.wardId : undefined;
  const areaId = typeof params.areaId === "string" ? params.areaId : undefined;
  const latitude =
    typeof params.lat === "string" ? Number(params.lat) : undefined;
  const longitude =
    typeof params.lng === "string" ? Number(params.lng) : undefined;
  const searchText = typeof params.q === "string" ? params.q.trim() : undefined;
  const categorySlug =
    typeof params.category === "string" ? params.category : undefined;
  const parsedMinPrice =
    typeof params.minPrice === "string" ? Number(params.minPrice) : NaN;
  const parsedMaxPrice =
    typeof params.maxPrice === "string" ? Number(params.maxPrice) : NaN;
  const minPrice = Number.isFinite(parsedMinPrice) ? parsedMinPrice : undefined;
  const maxPrice = Number.isFinite(parsedMaxPrice) ? parsedMaxPrice : undefined;
  const pricePeriod =
    typeof params.pricePeriod === "string" ? params.pricePeriod : undefined;
  const requestedSort =
    typeof params.sort === "string" ? params.sort : "recommended";
  const sort = (
    ["recommended", "newest", "price_low", "price_high"] as const
  ).includes(requestedSort as never)
    ? (requestedSort as "recommended" | "newest" | "price_low" | "price_high")
    : "recommended";
  const [categories, rawFeed, promotions, featuredRows] = await Promise.all([
    fetchCategories(),
    fetchPublicListings({
      limit: pageSize,
      page: currentPage - 1,
      regionId,
      districtId,
      wardId,
      areaId,
      latitude,
      longitude,
      sessionSeed: "listings",
      searchText,
      categorySlug,
      minPrice,
      maxPrice,
      pricePeriod,
      sort,
    }),
    fetchPromotions({ surface: "website", placement: "website", limit: 2 }),
    fetchActiveFeaturedListingIds(),
  ]);
  const featured = new Map(
    featuredRows.map((row) => [row.listing_id, row.placement]),
  );
  const feed: Array<Record<string, unknown> & { listing_id: string }> = (
    rawFeed as Array<Record<string, unknown> & { listing_id: string }>
  ).map((row) => ({
    ...row,
    featured: featured.has(row.listing_id),
    featured_placement: featured.get(row.listing_id),
  }));
  const totalCount = Number(rawFeed[0]?.total_count ?? feed.length);

  return (
    <PageShell className="pb-20">
      <PageHero
        eyebrow={sw ? "Soko la mali" : "Marketplace"}
        title={
          sw
            ? "Chagua na ulinganishe mali kwa urahisi."
            : "Browse and compare available listings."
        }
        description={
          sw
            ? "Pitia mali zinazopatikana, linganisha aina na bei, kisha fungua tangazo linalokufaa."
            : "Browse available listings, compare categories and prices, then open the listing that suits you."
        }
        actions={
          <BackNavButton
            fallbackHref="/"
            label={sw ? "Rudi nyumbani" : "Back to home"}
          />
        }
        aside={
          <div>
            <p className="eyebrow">{sw ? "Muhtasari" : "Quick view"}</p>
            <p className="mt-3 text-3xl font-heading font-semibold text-brand-ink">
              {totalCount}
            </p>
            <p className="section-copy mt-2 text-sm">
              {sw
                ? `Ukurasa wa ${currentPage} wa matangazo.`
                : `Marketplace listings page ${currentPage}.`}
            </p>
          </div>
        }
      />

      <section className="mt-6 flex flex-wrap gap-3">
        {categories.map(
          (category: { id: string; slug: string; name: string }) => (
            <Link
              key={category.id}
              href={`/category/${category.slug}`}
              className="btn btn-outline"
            >
              {category.name}
            </Link>
          ),
        )}
      </section>

      <form
        className="surface-card mt-6 grid gap-4 p-5 md:grid-cols-2 lg:grid-cols-4"
        action="/listings"
      >
        <label className="field-label">
          {sw ? "Tafuta" : "Search"}
          <input
            className="field-input mt-2"
            name="q"
            defaultValue={searchText}
            placeholder={
              sw ? "Nyumba, apartment, ofisi..." : "House, apartment, office..."
            }
          />
        </label>
        <label className="field-label">
          {sw ? "Aina ya mali" : "Category"}
          <select
            className="field-input mt-2"
            name="category"
            defaultValue={categorySlug ?? ""}
          >
            <option value="">{sw ? "Aina zote" : "All categories"}</option>
            {categories.map(
              (category: { id: string; slug: string; name: string }) => (
                <option key={category.id} value={category.slug}>
                  {category.name}
                </option>
              ),
            )}
          </select>
        </label>
        <label className="field-label">
          {sw ? "Bei ya chini" : "Minimum price"}
          <input
            className="field-input mt-2"
            name="minPrice"
            type="number"
            min="0"
            defaultValue={minPrice ?? ""}
          />
        </label>
        <label className="field-label">
          {sw ? "Bei ya juu" : "Maximum price"}
          <input
            className="field-input mt-2"
            name="maxPrice"
            type="number"
            min="0"
            defaultValue={maxPrice ?? ""}
          />
        </label>
        <label className="field-label">
          {sw ? "Kipindi cha bei" : "Price period"}
          <select
            className="field-input mt-2"
            name="pricePeriod"
            defaultValue={pricePeriod ?? ""}
          >
            <option value="">{sw ? "Kipindi chochote" : "Any period"}</option>
            <option value="hour">{sw ? "Kwa saa" : "Per hour"}</option>
            <option value="day">{sw ? "Kwa siku" : "Per day"}</option>
            <option value="week">{sw ? "Kwa wiki" : "Per week"}</option>
            <option value="month">{sw ? "Kwa mwezi" : "Per month"}</option>
            <option value="year">{sw ? "Kwa mwaka" : "Per year"}</option>
          </select>
        </label>
        <label className="field-label">
          {sw ? "Panga kwa" : "Sort by"}
          <select className="field-input mt-2" name="sort" defaultValue={sort}>
            <option value="recommended">
              {sw ? "Zilizopendekezwa" : "Recommended"}
            </option>
            <option value="newest">
              {sw ? "Mpya kwanza" : "Newest first"}
            </option>
            <option value="price_low">
              {sw ? "Bei ndogo kwanza" : "Lowest price"}
            </option>
            <option value="price_high">
              {sw ? "Bei kubwa kwanza" : "Highest price"}
            </option>
          </select>
        </label>
        <button className="btn btn-primary self-end">
          {sw ? "Tafuta mali" : "Search marketplace"}
        </button>
      </form>
      <div className="mt-4">
        <SaveSearchButton
          filters={{
            q: searchText ?? "",
            category: categorySlug ?? "",
            regionId: regionId ?? "",
            districtId: districtId ?? "",
            minPrice: minPrice == null ? "" : String(minPrice),
            maxPrice: maxPrice == null ? "" : String(maxPrice),
            pricePeriod: pricePeriod ?? "",
            sort,
          }}
        />
      </div>

      <PromotionStrip promotions={promotions as never} />
      <PublicListingGrid
        listings={feed as Array<{ listing_id: string }>}
        adSlot="home"
        clientId={adsenseClientId}
        slotId={adsenseHomeSlot}
      />
      <section className="mt-8 flex flex-wrap items-center justify-between gap-3">
        <p className="section-copy text-sm">Ukurasa {currentPage}</p>
        <div className="flex flex-wrap gap-3">
          {currentPage > 1 ? (
            <Link
              href={buildPageHref(params, currentPage - 1)}
              className="btn btn-outline"
            >
              Iliyopita
            </Link>
          ) : null}
          {feed.length === pageSize ? (
            <Link
              href={buildPageHref(params, currentPage + 1)}
              className="btn btn-primary"
            >
              Inayofuata
            </Link>
          ) : null}
        </div>
      </section>
      <GoogleAdSlot
        slot="home"
        clientId={adsenseClientId}
        slotId={adsenseHomeSlot}
      />
    </PageShell>
  );
}
