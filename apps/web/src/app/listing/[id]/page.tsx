import type { Metadata } from "next";
import Link from "next/link";

import { AgentContactCard } from "@/components/agent-contact-card";
import { BackNavButton } from "@/components/back-nav-button";
import { GuestRequestForm } from "@/components/guest-request-form";
import { GoogleAdSlot } from "@/components/google-ad-slot";
import { ListingMediaGallery } from "@/components/listing-media-gallery";
import { ListingShareButton } from "@/components/listing-share-button";
import { ListingActions, ListingViewRecorder } from "@/components/listing-actions";
import { PageShell } from "@/components/page-shell";
import { PromotionStrip } from "@/components/promotion-strip";
import { StatusPill } from "@/components/status-pill";
import { fetchListingDetail, fetchPromotions, fetchPublicListings } from "@/lib/supabase-public";
import { PublicListingCard } from "@/components/public-listing-card";

export const revalidate = 15;

export async function generateMetadata({
  params,
}: {
  params: Promise<{ id: string }>;
}): Promise<Metadata> {
  const { id } = await params;
  const listing = await fetchListingDetail(id);
  if (!listing) {
    return { title: "Listing unavailable" };
  }
  const description = `${listing.public_location_label ?? "Tanzania"} — TZS ${listing.price_amount ?? "-"} ${listing.price_period ?? ""}`;
  return {
    title: String(listing.title ?? "Rental listing"),
    description,
    alternates: { canonical: `/listing/${id}` },
    openGraph: { title: String(listing.title ?? "Rental listing"), description },
  };
}

function displayValue(value: unknown) {
  if (Array.isArray(value)) {
    return value.join(", ");
  }
  if (typeof value === "boolean") {
    return value ? "Ndiyo" : "Hapana";
  }
  return String(value ?? "-");
}

function formatAttributeLabel(key: string) {
  return key
    .replace(/_/g, " ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function farmHighlights(attributes: Record<string, unknown>) {
  return [
    {
      label: "Water availability",
      value: displayValue(attributes.water_availability),
    },
    {
      label: "Best crops",
      value: displayValue(attributes.best_crops),
    },
    {
      label: "Land size",
      value: [
        attributes.land_size ? String(attributes.land_size) : "",
        attributes.land_size_unit ? String(attributes.land_size_unit) : "",
      ]
        .filter(Boolean)
        .join(" ") || "-",
    },
  ];
}

function apartmentServices(attributes: Record<string, unknown>) {
  const options = [
    {
      key: "wifi_available",
      label: "WiFi",
    },
    {
      key: "food_available",
      label: "Food",
    },
    {
      key: "transport_available",
      label: "Transport",
    },
    {
      key: "cleaning_available",
      label: "Cleaning",
    },
    {
      key: "laundry_available",
      label: "Laundry",
    },
  ];

  return options.filter((item) => attributes[item.key] === true);
}

export default async function ListingPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const adsenseClientId = process.env.ADSENSE_CLIENT_ID ?? "";
  const adsenseDetailSlot = process.env.ADSENSE_SLOT_DETAIL ?? "";
  const { id } = await params;
  const [listing, promotions] = await Promise.all([
    fetchListingDetail(id),
    fetchPromotions({ surface: "website", placement: "listing_detail", limit: 1 }),
  ]);

  if (!listing) {
    return (
      <PageShell>
        <div className="surface-card rounded-[20px] p-8">Listing not found.</div>
      </PageShell>
    );
  }

  const attributes = (listing.listing_attributes ?? {}) as Record<string, unknown>;
  const similar = (await fetchPublicListings({ categorySlug: listing.asset_categories?.slug, limit: 4, page: 0, sessionSeed: `similar-${id}` })).filter((item: { listing_id: string }) => item.listing_id !== id).slice(0, 3);
  const fieldSchema = Array.isArray(listing.asset_categories?.field_schema)
    ? (listing.asset_categories.field_schema as Array<{
        key?: string;
        label?: string;
        active?: boolean;
      }>)
    : [];
  const showFarmHighlights = listing.asset_categories?.slug === "farms";
  const showApartmentServices = listing.asset_categories?.slug === "apartment";
  const highlights = showFarmHighlights ? farmHighlights(attributes) : [];
  const services = showApartmentServices ? apartmentServices(attributes) : [];
  const media = ((listing.listing_media ?? []) as Array<{
    media_type?: string | null;
    signed_url?: string | null;
    display_order?: number | null;
  }>).sort(
    (left, right) => (left.display_order ?? 0) - (right.display_order ?? 0),
  );
  const schemaByKey = new Map(fieldSchema.map((field) => [field.key, field]));
  const attributeEntries = Object.entries(attributes)
    .filter(([key, value]) => {
      const field = schemaByKey.get(key);
      return (
        field?.active !== false &&
        value !== null &&
        value !== undefined &&
        String(value).trim() !== ""
      );
    })
    .map(([key, value]) => ({
      key,
      label: schemaByKey.get(key)?.label ?? formatAttributeLabel(key),
      value,
    }));

  return (
    <PageShell className="pb-20">
      <ListingViewRecorder listingId={id} />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify({ "@context": "https://schema.org", "@type": "Offer", name: listing.title, description: listing.description, price: listing.price_amount, priceCurrency: "TZS", availability: "https://schema.org/InStock", areaServed: listing.public_location_label, url: `https://kodimali.co.tz/listing/${id}` }).replaceAll("<", "\\u003c") }} />
      <div className="mb-4">
        <BackNavButton fallbackHref="/listings" label="Back" />
      </div>
      <div className="grid gap-6 lg:grid-cols-[1.2fr_0.8fr]">
        <section className="surface-card rounded-[20px] p-6 sm:p-8">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div>
              <p className="eyebrow">{listing.asset_categories?.name ?? "Listing"}</p>
              <h1 className="mt-3 font-heading text-4xl font-semibold text-brand-ink">
                {listing.title}
              </h1>
              <p className="section-copy mt-3 text-base sm:text-lg">
                {listing.public_location_label}
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              <StatusPill label="Public listing" tone="active" />
              <StatusPill label="Verified flow" tone="info" />
            </div>
          </div>

          <div className="navy-panel mt-6 p-5 sm:p-6">
            <p className="text-sm font-semibold uppercase tracking-[0.18em] text-white/70">
              Price
            </p>
            <p className="mt-3 font-heading text-3xl font-semibold text-white">
              TZS {listing.price_amount}
            </p>
            <p className="mt-2 text-sm text-white/78">{listing.price_period}</p>
          </div>

          <p className="section-copy mt-6 text-base">
            {listing.description ?? "Maelezo zaidi yatathibitishwa na wakala."}
          </p>

          <div className="mt-6 flex flex-wrap gap-3">
            <ListingShareButton title={String(listing.title)} />
            <Link href="/listings" className="btn btn-outline">
              Rudi kwenye listings
            </Link>
          </div>
          <ListingActions listingId={id} />

          <ListingMediaGallery media={media} title={listing.title} />

          {showFarmHighlights ? (
            <div className="soft-panel mt-8 p-5">
              <p className="eyebrow">Farm highlights</p>
              <div className="mt-4 grid gap-3 sm:grid-cols-3">
                {highlights.map((item) => (
                  <div
                    key={item.label}
                    className="rounded-[16px] border border-brand-border bg-card px-4 py-4"
                  >
                    <p className="eyebrow text-[0.7rem]">{item.label}</p>
                    <p className="mt-3 text-base font-semibold text-brand-ink">
                      {item.value}
                    </p>
                  </div>
                ))}
              </div>
            </div>
          ) : null}

          {showApartmentServices && services.length > 0 ? (
            <div className="soft-panel mt-8 p-5">
              <p className="eyebrow">Available services</p>
              <div className="mt-4 flex flex-wrap gap-2">
                {services.map((service) => (
                  <span
                    key={service.key}
                    className="rounded-full border border-brand-border-strong bg-card px-4 py-2 text-sm font-semibold text-brand-navy"
                  >
                    {service.label}
                  </span>
                ))}
              </div>
            </div>
          ) : null}

          {attributeEntries.length > 0 ? (
            <div className="soft-panel mt-8 p-5">
              <p className="eyebrow">Additional details</p>
              <div className="mt-4 grid gap-3 sm:grid-cols-2">
                {attributeEntries.map(({ key, label, value }) => (
                  <div
                    key={key}
                    className="rounded-[16px] border border-brand-border bg-card px-4 py-3 text-sm text-muted"
                  >
                    <span className="font-bold text-brand-ink">
                      {label}
                    </span>
                    : {displayValue(value)}
                  </div>
                ))}
              </div>
            </div>
          ) : null}
        </section>

        <aside className="space-y-6 lg:sticky lg:top-32 lg:self-start">
          <AgentContactCard
            listingId={id}
            agentSummary={listing.agent_summary as never}
          />
          <GuestRequestForm
            listingId={id}
            listingTitle={listing.title}
            categorySlug={listing.asset_categories?.slug}
            availableServices={services}
          />
          <PromotionStrip promotions={promotions as never} />
          <GoogleAdSlot
            slot="detail"
            clientId={adsenseClientId}
            slotId={adsenseDetailSlot}
          />
        </aside>
      </div>
      {similar.length > 0 ? <section className="mt-10"><p className="eyebrow">Similar listings</p><h2 className="mt-2 font-heading text-3xl font-semibold">You may also consider</h2><div className="mt-6 grid gap-5 md:grid-cols-3">{similar.map((item: { listing_id: string }) => <PublicListingCard key={item.listing_id} listing={item as never} />)}</div></section> : null}
    </PageShell>
  );
}
