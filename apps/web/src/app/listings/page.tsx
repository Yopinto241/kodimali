import { BackNavButton } from "@/components/back-nav-button";
import Link from "next/link";

import { GoogleAdSlot } from "@/components/google-ad-slot";
import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";
import { PromotionStrip } from "@/components/promotion-strip";
import { PublicListingGrid } from "@/components/public-listing-grid";
import {
  fetchCategories,
  fetchPromotions,
  fetchPublicListings,
} from "@/lib/supabase-public";

export const revalidate = 120;

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
  const params = await searchParams;
  const adsenseClientId = process.env.ADSENSE_CLIENT_ID ?? "";
  const adsenseHomeSlot = process.env.ADSENSE_SLOT_HOME ?? "";
  const currentPage = Math.max(
    1,
    typeof params.page === "string" ? Number.parseInt(params.page, 10) || 1 : 1,
  );
  const regionId = typeof params.regionId === "string" ? params.regionId : undefined;
  const districtId =
    typeof params.districtId === "string" ? params.districtId : undefined;
  const wardId = typeof params.wardId === "string" ? params.wardId : undefined;
  const areaId = typeof params.areaId === "string" ? params.areaId : undefined;
  const latitude = typeof params.lat === "string" ? Number(params.lat) : undefined;
  const longitude = typeof params.lng === "string" ? Number(params.lng) : undefined;
  const [categories, feed, promotions] = await Promise.all([
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
    }),
    fetchPromotions({ surface: "website", placement: "website", limit: 2 }),
  ]);

  return (
    <PageShell className="pb-20">
      <PageHero
        eyebrow="Marketplace"
        title="Open listings you can compare clearly."
        description="Pitia mali zilizo active, linganisha category na bei, kisha fungua detail ya listing inayokuvutia zaidi."
        actions={<BackNavButton fallbackHref="/" label="Back to home" />}
        aside={
          <div>
            <p className="eyebrow">Quick view</p>
            <p className="mt-3 text-3xl font-heading font-semibold text-brand-ink">
              {feed.length}
            </p>
            <p className="section-copy mt-2 text-sm">
              Page {currentPage} ya marketplace listings.
            </p>
          </div>
        }
      />

      <section className="mt-6 flex flex-wrap gap-3">
        {categories.map((category: { id: string; slug: string; name: string }) => (
          <Link
            key={category.id}
            href={`/category/${category.slug}`}
            className="btn btn-outline"
          >
            {category.name}
          </Link>
        ))}
      </section>

      <PromotionStrip promotions={promotions as never} />
      <PublicListingGrid
        listings={feed as Array<{ listing_id: string }>}
        adSlot="home"
        clientId={adsenseClientId}
        slotId={adsenseHomeSlot}
      />
      <section className="mt-8 flex flex-wrap items-center justify-between gap-3">
        <p className="section-copy text-sm">
          Unapata batch ndogo ya listings kwa kila page ili tovuti ifunguke haraka.
        </p>
        <div className="flex flex-wrap gap-3">
          {currentPage > 1 ? (
            <Link href={buildPageHref(params, currentPage - 1)} className="btn btn-outline">
              Page iliyopita
            </Link>
          ) : null}
          {feed.length === pageSize ? (
            <Link href={buildPageHref(params, currentPage + 1)} className="btn btn-primary">
              Page inayofuata
            </Link>
          ) : null}
        </div>
      </section>
      <GoogleAdSlot slot="home" clientId={adsenseClientId} slotId={adsenseHomeSlot} />
    </PageShell>
  );
}
