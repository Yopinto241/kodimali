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

export const dynamic = "force-dynamic";

export default async function ListingsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const adsenseClientId = process.env.ADSENSE_CLIENT_ID ?? "";
  const adsenseHomeSlot = process.env.ADSENSE_SLOT_HOME ?? "";
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
      limit: 30,
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
        aside={
          <div>
            <p className="eyebrow">Quick view</p>
            <p className="mt-3 text-3xl font-heading font-semibold text-brand-ink">
              {feed.length}
            </p>
            <p className="section-copy mt-2 text-sm">
              listings zimepangwa kwa urahisi kwenye page hii.
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
      <GoogleAdSlot slot="home" clientId={adsenseClientId} slotId={adsenseHomeSlot} />
    </PageShell>
  );
}
