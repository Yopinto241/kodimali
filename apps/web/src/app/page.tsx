import Link from "next/link";

import { GoogleAdSlot } from "@/components/google-ad-slot";
import { LocationBanner } from "@/components/location-banner";
import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";
import { PromotionStrip } from "@/components/promotion-strip";
import { PublicListingCard } from "@/components/public-listing-card";
import { SectionHeading } from "@/components/section-heading";
import { StatusPill } from "@/components/status-pill";
import { roleCards } from "@/lib/site-content";
import {
  fetchCategories,
  fetchCountryId,
  fetchLocations,
  fetchPromotions,
  fetchPublicHomeFeed,
} from "@/lib/supabase-public";

export const revalidate = 120;

export default async function Home({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const adsenseClientId = process.env.ADSENSE_CLIENT_ID ?? "";
  const adsenseHomeSlot = process.env.ADSENSE_SLOT_HOME ?? "";
  const params = await searchParams;
  const regionId = typeof params.regionId === "string" ? params.regionId : undefined;
  const districtId =
    typeof params.districtId === "string" ? params.districtId : undefined;
  const wardId = typeof params.wardId === "string" ? params.wardId : undefined;
  const areaId = typeof params.areaId === "string" ? params.areaId : undefined;
  const latitude = typeof params.lat === "string" ? Number(params.lat) : undefined;
  const longitude = typeof params.lng === "string" ? Number(params.lng) : undefined;

  const countryId = await fetchCountryId();
  const [categories, feed, regions, promotions] = await Promise.all([
    fetchCategories(),
    fetchPublicHomeFeed({
      limit: 12,
      regionId,
      districtId,
      wardId,
      areaId,
      latitude,
      longitude,
      sessionSeed: "home",
    }),
    countryId
      ? fetchLocations({ locationType: "region", parentId: countryId })
      : Promise.resolve([]),
    fetchPromotions({ surface: "website", placement: "global", limit: 2 }),
  ]);

  const section = (title: string, slugs: string[]) => {
    const listings = feed.filter((item: { category_slug: string }) =>
      slugs.includes(item.category_slug),
    );

    if (listings.length === 0) {
      return null;
    }

    return (
      <section className="py-6">
        <SectionHeading
          eyebrow="Marketplace"
          title={title}
          description="Angalia mali zenye picha, bei, na eneo la jumla kabla ya kutuma ombi lako."
        />
        <div className="mt-6 grid gap-6 md:grid-cols-2">
          {listings.map((listing: { listing_id: string }) => (
            <PublicListingCard key={listing.listing_id} listing={listing as never} />
          ))}
        </div>
      </section>
    );
  };

  return (
    <PageShell className="flex flex-col pb-20">
      <PageHero
        eyebrow="Trusted marketplace"
        title="Mali halisi. Wakala waliothibitishwa. Ombi rahisi bila akaunti."
        description="KODIMALI hukusaidia kuona listings zilizo wazi, kuchagua eneo lako, na kutuma ombi moja kwa moja kwa wakala anayehusika bila kufichua taarifa nyingi zisizo lazima."
        actions={
          <>
            <Link href="/listings" className="btn btn-primary">
              Fungua listings
            </Link>
            <a href="#categories" className="btn btn-outline">
              Angalia categories
            </a>
          </>
        }
        aside={
          <div>
            <div className="flex flex-wrap gap-2">
              <StatusPill label="Verified agents" tone="active" />
              <StatusPill label="Secure request" tone="info" />
            </div>
            <p className="mt-4 text-lg font-semibold text-brand-ink">
              Utaona picha, bei, na eneo la jumla kabla ya kuwasiliana.
            </p>
            <p className="section-copy mt-3 text-sm">
              Tunazuia mtindo wa kelele za social media na kuweka hatua kuu karibu:
              tafuta, linganisha, kisha tuma ombi.
            </p>
          </div>
        }
      />

      <section className="grid gap-4 py-6 md:grid-cols-3">
        <article className="surface-card rounded-[20px] p-5">
          <StatusPill label="Active" tone="active" />
          <h2 className="mt-4 font-heading text-xl font-semibold text-brand-ink">
            Wakala wanaoweza kufuatilia ombi lako
          </h2>
          <p className="section-copy mt-3 text-sm">
            Ombi linaenda kwa wakala anayesimamia listing hiyo, si kwa watu wengi bila
            mpangilio.
          </p>
        </article>
        <article className="surface-card rounded-[20px] p-5">
          <StatusPill label="Private" tone="info" />
          <h2 className="mt-4 font-heading text-xl font-semibold text-brand-ink">
            Eneo linaonekana kwa usalama
          </h2>
          <p className="section-copy mt-3 text-sm">
            Unaona context ya location bila kuonyesha address kamili au GPS ya siri
            hadharani.
          </p>
        </article>
        <article className="surface-card rounded-[20px] p-5">
          <StatusPill label="Simple" tone="pending" />
          <h2 className="mt-4 font-heading text-xl font-semibold text-brand-ink">
            Hatua kuu iko wazi kila ukurasa
          </h2>
          <p className="section-copy mt-3 text-sm">
            Kwenye KODIMALI, hatua kuu ni kutazama detail na kutuma ombi kwa urahisi.
          </p>
        </article>
      </section>

      <form action="/listings" className="surface-card my-6 grid gap-4 p-5 md:grid-cols-[1fr_260px_auto] sm:p-7">
        <label className="field-label">What are you looking for?<input className="field-input mt-2" name="q" placeholder="Apartment, house, office, car..." /></label>
        <label className="field-label">Category<select className="field-input mt-2" name="category"><option value="">All categories</option>{categories.map((category: { id: string; slug: string; name: string }) => <option key={category.id} value={category.slug}>{category.name}</option>)}</select></label>
        <button className="btn btn-success self-end">Search now</button>
      </form>

      <section className="py-2">
        <LocationBanner
          visibleByDefault
          regions={regions.map((item: { id: string; name: string }) => ({
            id: item.id,
            name: item.name,
          }))}
        />
      </section>

      <section className="py-6"><SectionHeading eyebrow="Popular locations" title="Discover listings by region" description="Start broadly, then narrow down to district, ward and area without exposing private property coordinates." /><div className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">{regions.slice(0, 8).map((region: { id: string; name: string }) => <Link className="surface-card p-5 font-bold text-brand-navy transition hover:-translate-y-1" href={`/listings?regionId=${region.id}`} key={region.id}>{region.name}<span className="mt-2 block text-xs font-normal text-muted">Explore this region →</span></Link>)}</div></section>

      <PromotionStrip promotions={promotions as never} />
      <GoogleAdSlot
        slot="home"
        clientId={adsenseClientId}
        slotId={adsenseHomeSlot}
      />

      <section id="categories" className="py-6">
        <SectionHeading
          eyebrow="Browse categories"
          title="Anza na category inayokufaa"
          description="Chagua aina ya mali unayotafuta, kisha uende moja kwa moja kwenye listings zake."
        />
        <div className="mt-6 flex flex-wrap gap-3">
          {categories.map((category: { id: string; slug: string; name: string }) => (
            <Link
              key={category.id}
              href={`/category/${category.slug}`}
              className="btn btn-outline"
            >
              {category.name}
            </Link>
          ))}
        </div>
      </section>

      <section className="py-6">
        <SectionHeading
          eyebrow="One product"
          title="KODIMALI inabaki na mwonekano mmoja hata inavyokua"
          description="Kila surface ina kazi yake, lakini lugha ya vitendo, cards, na trust signals vinabaki vilevile."
        />
        <div className="mt-6 grid gap-4 md:grid-cols-3">
          {roleCards.map((card) => (
            <Link
              key={card.title}
              href={card.href}
              className="surface-card rounded-[20px] p-5 transition hover:-translate-y-1"
            >
              <p className="eyebrow">Product surface</p>
              <h3 className="mt-3 font-heading text-2xl font-semibold text-brand-ink">
                {card.title}
              </h3>
              <p className="section-copy mt-3 text-sm">{card.description}</p>
              <p className="mt-4 text-sm font-bold text-brand-navy">Open surface</p>
            </Link>
          ))}
        </div>
      </section>

      <section className="grid gap-5 py-8 md:grid-cols-2"><article className="navy-panel p-7"><p className="text-xs font-bold uppercase tracking-[0.2em] text-brand-green">KODIMALI mobile</p><h2 className="mt-3 font-heading text-3xl font-semibold">Get alerts and manage activity anywhere</h2><p className="mt-3 text-white/75">Install the customer or manage app for push notifications, synchronized chats and quicker workflows.</p><Link href="/download" className="btn btn-success mt-5">View mobile apps</Link></article><article className="surface-card p-7"><p className="eyebrow">Business growth</p><h2 className="mt-3 font-heading text-3xl font-semibold">Promote listings and campaigns</h2><p className="section-copy mt-3">Reach customers with measured sponsored campaigns, featured listings and agent plans.</p><Link href="/advertise" className="btn btn-primary mt-5">Advertising options</Link></article></section>

      {section(
        "Karibu na wewe",
        feed.slice(0, 6).map((item: { category_slug: string }) => item.category_slug),
      )}
      {section("Apartment stays", ["apartment"])}
      {section("Nyumba za kupangisha", ["house"])}
      {section("Magari na pikipiki", ["car", "motorcycle"])}
      {section("Ofisi na kumbi", ["office", "meeting-hall", "ceremony-hall"])}
      {section(
        "Matangazo mengine",
        categories
          .map((category: { slug: string }) => category.slug)
          .filter(
            (slug: string) =>
              !["apartment", "house", "car", "motorcycle", "office", "meeting-hall", "ceremony-hall"].includes(
                slug,
              ),
          ),
      )}
    </PageShell>
  );
}
