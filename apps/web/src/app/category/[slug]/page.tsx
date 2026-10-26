import Link from "next/link";

import { BackNavButton } from "@/components/back-nav-button";
import { GoogleAdSlot } from "@/components/google-ad-slot";
import { LocationBanner } from "@/components/location-banner";
import { PageShell } from "@/components/page-shell";
import { PromotionStrip } from "@/components/promotion-strip";
import { PublicListingGrid } from "@/components/public-listing-grid";
import {
  fetchCategories,
  fetchCountryId,
  fetchLocations,
  fetchPromotions,
  fetchPublicListings,
} from "@/lib/supabase-public";

export const revalidate = 120;

const pageSize = 20;

function buildPageHref(
  slug: string,
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
  return serialized ? `/category/${slug}?${serialized}` : `/category/${slug}`;
}

export default async function CategoryPage({
  params,
  searchParams,
}: {
  params: Promise<{ slug: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const adsenseClientId = process.env.ADSENSE_CLIENT_ID ?? "";
  const adsenseCategorySlot = process.env.ADSENSE_SLOT_CATEGORY ?? "";
  const { slug } = await params;
  const query = await searchParams;
  const currentPage = Math.max(
    1,
    typeof query.page === "string" ? Number.parseInt(query.page, 10) || 1 : 1,
  );
  const regionId = typeof query.regionId === "string" ? query.regionId : undefined;
  const districtId =
    typeof query.districtId === "string" ? query.districtId : undefined;
  const wardId = typeof query.wardId === "string" ? query.wardId : undefined;
  const areaId = typeof query.areaId === "string" ? query.areaId : undefined;
  const latitude = typeof query.lat === "string" ? Number(query.lat) : undefined;
  const longitude = typeof query.lng === "string" ? Number(query.lng) : undefined;
  const countryId = await fetchCountryId();
  const [categories, listings, promotions, regions] = await Promise.all([
    fetchCategories(),
    fetchPublicListings({
      categorySlug: slug,
      limit: pageSize,
      page: currentPage - 1,
      regionId,
      districtId,
      wardId,
      areaId,
      latitude,
      longitude,
      sessionSeed: slug,
    }),
    fetchPromotions({ surface: "website", placement: "category_page", limit: 1 }),
    countryId
      ? fetchLocations({ locationType: "region", parentId: countryId })
      : Promise.resolve([]),
  ]);
  const category = categories.find((item: { slug: string }) => item.slug === slug);

  return (
    <PageShell className="pb-20">
      <section className="category-browser-head">
        <div className="flex items-center gap-3">
          <BackNavButton fallbackHref="/" label="Nyuma" />
          <div className="min-w-0 flex-1">
            <h1>{category?.name ?? slug}</h1>
            <p>{listings.length} zinapatikana kwenye ukurasa huu</p>
          </div>
          <Link href={`/listings?category=${encodeURIComponent(slug)}`} className="category-search-icon" aria-label="Tafuta">⌕</Link>
        </div>
        <form action="/listings" className="category-inline-search">
          <span aria-hidden="true">⌕</span>
          <input name="q" placeholder={`Tafuta ${category?.name ?? slug}`} aria-label={`Tafuta ${category?.name ?? slug}`} />
          <input type="hidden" name="category" value={slug} />
          <button>Tafuta</button>
        </form>
        <div className="category-browser-controls">
          <details>
            <summary>⌖ {regionId || districtId || wardId || areaId ? "Eneo limechaguliwa" : "Chagua eneo"}</summary>
            <div className="category-location-panel">
              <LocationBanner
                visibleByDefault
                persistent
                regions={regions.map((item: { id: string; name: string }) => ({ id: item.id, name: item.name }))}
              />
            </div>
          </details>
          <Link href={`/listings?category=${encodeURIComponent(slug)}`} className="category-control-chip">Aina</Link>
          <Link href={`/listings?category=${encodeURIComponent(slug)}#filters`} className="category-control-chip">Bei</Link>
          <Link href={`/listings?category=${encodeURIComponent(slug)}#filters`} className="category-control-chip">☷ Chuja</Link>
        </div>
      </section>

      <PromotionStrip promotions={promotions as never} />
      <PublicListingGrid
        listings={listings as Array<{ listing_id: string }>}
        adSlot="category"
        clientId={adsenseClientId}
        slotId={adsenseCategorySlot}
      />
      <section className="mt-8 flex flex-wrap items-center justify-between gap-3">
        <p className="section-copy text-sm">Ukurasa {currentPage}</p>
        <div className="flex flex-wrap gap-3">
          {currentPage > 1 ? (
            <Link href={buildPageHref(slug, query, currentPage - 1)} className="btn btn-outline">
              Iliyopita
            </Link>
          ) : null}
          {listings.length === pageSize ? (
            <Link href={buildPageHref(slug, query, currentPage + 1)} className="btn btn-primary">
              Inayofuata
            </Link>
          ) : null}
        </div>
      </section>
      <GoogleAdSlot
        slot="category"
        clientId={adsenseClientId}
        slotId={adsenseCategorySlot}
      />
    </PageShell>
  );
}
