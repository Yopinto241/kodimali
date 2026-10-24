import Link from "next/link";
import { DirectMediaImage } from "@/components/direct-media-image";
import { StatusPill } from "@/components/status-pill";
import { SquareMediaVideo } from "@/components/square-media-video";
import { ListingActions } from "@/components/listing-actions";

type Listing = {
  listing_id: string;
  title: string;
  public_location_label: string;
  price_amount: string | number;
  price_period: string;
  category_name: string;
  cover_url?: string | null;
  cover_media_type?: string | null;
  featured?: boolean;
  featured_placement?: string | null;
};

export function PublicListingCard({ listing, priority = false }: { listing: Listing; priority?: boolean }) {
  return (
    <article className="surface-card group block overflow-hidden rounded-[24px] p-3 transition duration-200 hover:-translate-y-1 hover:shadow-[0_28px_60px_rgba(16,36,56,0.14)]">
      <Link href={`/listing/${listing.listing_id}`} className="block">
      <div className="mb-3 flex items-start justify-between gap-4 px-2 pt-2">
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
            <p className="truncate text-sm text-muted">{listing.public_location_label}</p>
          </div>
        </div>
        <div className="flex flex-col items-end gap-2"><StatusPill label="Verified" tone="active" />{listing.featured ? <StatusPill label={listing.featured_placement === "homepage" ? "Homepage featured" : "Featured"} tone="pending" /> : null}</div>
      </div>
      <div className="relative overflow-hidden rounded-[18px] bg-brand-card-soft">
        {listing.cover_url && listing.cover_media_type === "video" ? (
          <SquareMediaVideo src={listing.cover_url} controls={false} />
        ) : listing.cover_url ? (
          <DirectMediaImage
            src={listing.cover_url}
            alt={listing.title}
            sizes="(min-width: 1280px) 560px, (min-width: 768px) calc(50vw - 48px), calc(100vw - 32px)"
            className="aspect-[4/3] w-full object-cover transition duration-500 group-hover:scale-[1.025]"
            priority={priority}
          />
        ) : (
          <div className="flex aspect-[4/3] w-full items-center justify-center bg-brand-surface text-muted">
            Hakuna picha
          </div>
        )}
        <div className="absolute left-4 top-4 rounded-full bg-brand-navy px-4 py-2 text-sm font-semibold text-white shadow-sm">
          TZS {listing.price_amount} / {listing.price_period}
        </div>
      </div>
      <div className="px-2 pb-2 pt-4">
        <h3 className="font-heading text-xl font-semibold text-brand-ink">
          {listing.title}
        </h3>
        <p className="mt-3 text-sm font-bold text-brand-teal">Tazama mali →</p>
      </div></Link>
      <ListingActions listingId={listing.listing_id} />
    </article>
  );
}
