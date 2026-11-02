import { UiText } from "@/components/ui-text";
import { CatalogFilters } from "@/components/catalog-filters";
import { catalogLocation } from "@/lib/catalog-location";
import { catalogMetadata, type SearchParams } from "@/lib/seo";
import Link from "next/link";
import { cookies } from "next/headers";

import { GoogleAdSlot } from "@/components/google-ad-slot";
import { PageShell } from "@/components/page-shell";
import { PublicListingGrid } from "@/components/public-listing-grid";
import { SaveSearchButton } from "@/components/save-search-button";
import { optionalNumber } from "@/lib/listing-search";
import {
  fetchCategories,
  fetchCountryId,
  fetchLocations,
  fetchPromotions,
  fetchPublicListings,
  fetchActiveFeaturedListingIds,
} from "@/lib/supabase-public";

export async function generateMetadata({ searchParams }: { searchParams: Promise<SearchParams> }) {
  return catalogMetadata("Mali za kukodisha Tanzania", "Linganisha nyumba, apartments, magari, ofisi, kumbi na vifaa vya kukodisha. Chagua eneo na bajeti, kisha tuma ombi kupitia KODIMALI.", "/listings", await searchParams);
}

export const revalidate = 60;

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
  const { regionId, districtId, wardId, areaId } = await catalogLocation(params);
  const searchText = typeof params.q === "string" ? params.q.trim() : undefined;
  const categorySlug =
    typeof params.category === "string" ? params.category : undefined;
  const minPrice = optionalNumber(params.minPrice, true);
  const maxPrice = optionalNumber(params.maxPrice, true);
  const pricePeriod =
    typeof params.pricePeriod === "string" ? params.pricePeriod : undefined;
  const requestedSort =
    typeof params.sort === "string" ? params.sort : "recommended";
  const sort = (
    ["recommended", "newest", "price_low", "price_high"] as const
  ).includes(requestedSort as never)
    ? (requestedSort as "recommended" | "newest" | "price_low" | "price_high")
    : "recommended";
  const countryId = await fetchCountryId();
  const [categories, rawFeed, promotions, featuredRows, regions, selectedDistricts, selectedWards, selectedAreas] = await Promise.all([
    fetchCategories(),
    fetchPublicListings({
      limit: pageSize,
      page: currentPage - 1,
      regionId,
      districtId,
      wardId,
      areaId,
      sessionSeed: "listings",
      searchText,
      categorySlug,
      minPrice,
      maxPrice,
      pricePeriod,
      sort,
    }),
    fetchPromotions({ surface: "website", placement: "website", categorySlug, regionId, districtId, wardId, areaId }),
    fetchActiveFeaturedListingIds(),
    countryId ? fetchLocations({ locationType: "region", parentId: countryId }) : Promise.resolve([]),
    regionId ? fetchLocations({ locationType: "district", parentId: regionId }) : Promise.resolve([]),
    districtId ? fetchLocations({ locationType: "ward", parentId: districtId }) : Promise.resolve([]),
    wardId ? fetchLocations({ locationType: "area", parentId: wardId }) : Promise.resolve([]),
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
      <h1 className="sr-only"><UiText text={sw ? "Mali za kukodisha Tanzania" : "Rentals in Tanzania"} /></h1>
      <CatalogFilters path="/listings" sw={sw} totalCount={totalCount} categories={categories} regions={regions} selectedDistricts={selectedDistricts} selectedWards={selectedWards} selectedAreas={selectedAreas} regionId={regionId} districtId={districtId} wardId={wardId} areaId={areaId} searchText={searchText} categorySlug={categorySlug} minPrice={minPrice} maxPrice={maxPrice} pricePeriod={pricePeriod} sort={sort} />
      <div className="mt-4">
        <SaveSearchButton
          filters={{
            q: searchText ?? "",
            category: categorySlug ?? "",
            regionId: regionId ?? "",
            districtId: districtId ?? "",
            wardId: wardId ?? "",
            areaId: areaId ?? "",
            minPrice: minPrice == null ? "" : String(minPrice),
            maxPrice: maxPrice == null ? "" : String(maxPrice),
            pricePeriod: pricePeriod ?? "",
            sort,
          }}
        />
      </div>

      <PublicListingGrid
        listings={feed as Array<{ listing_id: string }>}
        promotions={promotions as never}
        adSlot="home"
        clientId={adsenseClientId}
        slotId={adsenseHomeSlot}
      />
      <section className="mt-8 flex flex-wrap items-center justify-between gap-3">
        <p className="section-copy text-sm"><UiText text={"Ukurasa "} />{currentPage}</p>
        <div className="flex flex-wrap gap-3">
          {currentPage > 1 ? (
            <Link
              href={buildPageHref(params, currentPage - 1)}
              className="btn btn-outline"
            ><UiText text={"Iliyopita"} /></Link>
          ) : null}
          {feed.length === pageSize ? (
            <Link
              href={buildPageHref(params, currentPage + 1)}
              className="btn btn-primary"
            ><UiText text={"Inayofuata"} /></Link>
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
