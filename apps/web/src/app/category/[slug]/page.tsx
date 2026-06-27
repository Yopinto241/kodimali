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
  const regionId = typeof query.regionId === "string" ? query.regionId : undefined;
  const districtId =
    typeof query.districtId === "string" ? query.districtId : undefined;
  const wardId = typeof query.wardId === "string" ? query.wardId : undefined;
  const areaId = typeof query.areaId === "string" ? query.areaId : undefined;
  const latitude = typeof query.lat === "string" ? Number(query.lat) : undefined;
  const longitude = typeof query.lng === "string" ? Number(query.lng) : undefined;
  const [categories, listings, promotions] = await Promise.all([
    fetchCategories(),
    fetchPublicListings({
      categorySlug: slug,
      limit: 30,
      regionId,
      districtId,
      wardId,
      areaId,
      latitude,
      longitude,
      sessionSeed: slug,
    }),
    fetchPromotions({ surface: "website", placement: "category_page", limit: 1 }),
  ]);
  const category = categories.find((item: { slug: string }) => item.slug === slug);

  return (
    <PageShell className="pb-20">
      <PageHero
        eyebrow="Category"
        title={category?.name ?? slug}
        description={
          category?.description ??
          "Angalia listings zilizo kwenye kundi hili na fungua detail ya inayokufaa."
        }
        actions={
          <Link href="/listings" className="btn btn-outline">
            Rudi kwenye listings zote
          </Link>
        }
      />

      <PromotionStrip promotions={promotions as never} />
      <PublicListingGrid
        listings={listings as Array<{ listing_id: string }>}
        adSlot="category"
        clientId={adsenseClientId}
        slotId={adsenseCategorySlot}
      />
      <GoogleAdSlot
        slot="category"
        clientId={adsenseClientId}
        slotId={adsenseCategorySlot}
      />
    </PageShell>
  );
}
