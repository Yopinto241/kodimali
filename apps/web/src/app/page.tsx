import { GoogleAdSlot } from "@/components/google-ad-slot";
import { LocationBanner } from "@/components/location-banner";
import { RevealOnScroll } from "@/components/motion/reveal-on-scroll";
import { PageShell } from "@/components/page-shell";
import { CinematicHero } from "@/components/premium/cinematic-hero";
import { CategoryShowcase } from "@/components/premium/category-showcase";
import { CategoryListingRails } from "@/components/premium/category-listing-rails";
import { ReferralStorySection } from "@/components/premium/referral-story-section";
import { VerificationCard } from "@/components/verification-card";
import { PromotionStrip } from "@/components/promotion-strip";
import { fetchCategories, fetchCountryId, fetchLocations, fetchPromotions, fetchPublicHomeFeed } from "@/lib/supabase-public";

export const revalidate = 120;

export default async function Home({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const countryId = await fetchCountryId();
  const [categories, feed, regions, promotions] = await Promise.all([
    fetchCategories(),
    fetchPublicHomeFeed({
      limit: 60,
      regionId: typeof params.regionId === "string" ? params.regionId : undefined,
      districtId: typeof params.districtId === "string" ? params.districtId : undefined,
      wardId: typeof params.wardId === "string" ? params.wardId : undefined,
      areaId: typeof params.areaId === "string" ? params.areaId : undefined,
      latitude: typeof params.lat === "string" ? Number(params.lat) : undefined,
      longitude: typeof params.lng === "string" ? Number(params.lng) : undefined,
      sessionSeed: "home",
    }),
    countryId ? fetchLocations({ locationType: "region", parentId: countryId }) : Promise.resolve([]),
    fetchPromotions({ surface: "website", placement: "global", limit: 2 }),
  ]);

  return <>
    <CinematicHero categories={categories} />
    <PageShell className="flex flex-col pb-20">
      <CategoryShowcase categories={categories} feed={feed} />

      <RevealOnScroll><section className="py-4"><LocationBanner visibleByDefault regions={regions.map((item: { id: string; name: string }) => ({ id: item.id, name: item.name }))} /></section></RevealOnScroll>

      <PromotionStrip promotions={promotions as never} />
      <GoogleAdSlot slot="home" clientId={process.env.ADSENSE_CLIENT_ID ?? ""} slotId={process.env.ADSENSE_SLOT_HOME ?? ""} />

      <CategoryListingRails categories={categories} listings={feed} />

      <ReferralStorySection />

      <RevealOnScroll><VerificationCard /></RevealOnScroll>
    </PageShell>
  </>;
}
