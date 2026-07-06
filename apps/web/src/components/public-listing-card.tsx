import Link from "next/link";
import { DirectMediaImage } from "@/components/direct-media-image";
import { StatusPill } from "@/components/status-pill";

type Listing = {
  listing_id: string;
  title: string;
  public_location_label: string;
  price_amount: string | number;
  price_period: string;
  category_name: string;
  cover_url?: string | null;
};

export function PublicListingCard({ listing }: { listing: Listing }) {
  return (
    <Link
      href={`/listing/${listing.listing_id}`}
      className="surface-card block overflow-hidden rounded-[20px] p-5 transition hover:-translate-y-1 hover:shadow-[0_24px_48px_rgba(11,31,58,0.12)]"
    >
      <div className="mb-5 flex items-start justify-between gap-4">
        <div className="flex min-w-0 items-center gap-3">
          <div className="flex h-11 w-11 items-center justify-center rounded-full bg-brand-green-soft text-brand-navy">
            <span className="text-lg font-bold">
              {listing.category_name.slice(0, 1).toUpperCase()}
            </span>
          </div>
          <div className="min-w-0">
            <p className="truncate text-base font-semibold text-brand-ink">
              {listing.category_name}
            </p>
            <p className="truncate text-sm text-muted">
              Active marketplace listing
            </p>
          </div>
        </div>
        <StatusPill label="Verified" tone="active" />
      </div>
      <div className="relative overflow-hidden rounded-[16px] border border-brand-border bg-brand-card-soft">
        {listing.cover_url ? (
          <DirectMediaImage
            src={listing.cover_url}
            alt={listing.title}
            sizes="(min-width: 768px) 50vw, 100vw"
            className="aspect-[4/3] w-full object-cover"
          />
        ) : (
          <div className="flex aspect-[4/3] w-full items-center justify-center bg-brand-surface text-muted">
            Image loading soon
          </div>
        )}
        <div className="absolute left-4 top-4 rounded-full bg-brand-navy px-4 py-2 text-sm font-semibold text-white shadow-sm">
          TZS {listing.price_amount} / {listing.price_period}
        </div>
      </div>
      <div className="mt-5">
        <h3 className="font-heading text-2xl font-semibold text-brand-ink">
          {listing.title}
        </h3>
        <p className="mt-2 text-sm text-muted">{listing.public_location_label}</p>
        <p className="mt-3 text-sm leading-7 text-muted">
          Angalia picha kwa utulivu, soma maelezo muhimu, kisha tuma ombi lako kwa
          wakala anayehusika.
        </p>
        <p className="mt-4 text-sm font-bold text-brand-navy">Fungua detail</p>
      </div>
    </Link>
  );
}
