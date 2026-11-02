import { catalogLocation } from "@/lib/catalog-location";
import { catalogMetadata, HOME_TITLE, HOME_DESCRIPTION, type SearchParams } from "@/lib/seo";
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

export const revalidate = 15;

export async function generateMetadata({ searchParams }: { searchParams: Promise<SearchParams> }) { return catalogMetadata(HOME_TITLE, HOME_DESCRIPTION, "/", await searchParams); }

export default async function Home({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const location = await catalogLocation(params);
  const countryId = await fetchCountryId();
  const [categories, feed, regions, promotions] = await Promise.all([
    fetchCategories(),
    fetchPublicHomeFeed({
      limit: 60,
      regionId: location.regionId,
      districtId: location.districtId,
      wardId: location.wardId,
      areaId: location.areaId,
      sessionSeed: "home",
    }),
    countryId ? fetchLocations({ locationType: "region", parentId: countryId }) : Promise.resolve([]),
    fetchPromotions({ surface: "website", placement: "home_feed", regionId: location.regionId, districtId: location.districtId, wardId: location.wardId, areaId: location.areaId }),
  ]);

  return <>
    <CinematicHero />
    <PageShell className="home-page-shell flex flex-col pb-20 !pt-0">
      <CategoryShowcase categories={categories} feed={feed} />

      <CategoryListingRails categories={categories} listings={feed} />
      <PromotionStrip promotions={promotions as never} />

      <RevealOnScroll><section className="py-4"><LocationBanner visibleByDefault initialLocation={{regionId: location.regionId, districtId: location.districtId, wardId: location.wardId, areaId: location.areaId}} regions={regions.map((item: { id: string; name: string }) => ({ id: item.id, name: item.name }))} /></section></RevealOnScroll>

      <GoogleAdSlot slot="home" clientId={process.env.ADSENSE_CLIENT_ID ?? ""} slotId={process.env.ADSENSE_SLOT_HOME ?? ""} />

      <ReferralStorySection />

      <RevealOnScroll><VerificationCard /></RevealOnScroll>
    </PageShell>
  </>;
}
