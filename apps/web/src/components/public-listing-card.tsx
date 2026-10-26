import Link from "next/link";
import { DirectMediaImage } from "@/components/direct-media-image";
import { SquareMediaVideo } from "@/components/square-media-video";
import { ListingActions } from "@/components/listing-actions";

type Listing = {
  listing_id: string;
  title: string;
  public_location_label: string;
  price_amount: string | number;
  price_period: string;
  category_name: string;
  category_slug?: string | null;
  cover_url?: string | null;
  cover_media_type?: string | null;
  featured?: boolean;
  featured_placement?: string | null;
};

const reservableCategories = new Set([
  "house",
  "apartment",
  "car",
  "motorcycle",
  "office",
  "meeting-hall",
  "ceremony-hall",
]);

export function PublicListingCard({
  listing,
  priority = false,
}: {
  listing: Listing;
  priority?: boolean;
}) {
  const category = String(listing.category_slug ?? listing.category_name ?? "")
    .toLowerCase()
    .replaceAll(" ", "-");
  const canBook = reservableCategories.has(category);
  return (
    <article className="listing-card group">
      <Link href={`/listing/${listing.listing_id}`} className="block">
        <div className="listing-card-media">
          {listing.cover_url && listing.cover_media_type === "video" ? (
            <SquareMediaVideo src={listing.cover_url} controls={false} />
          ) : listing.cover_url ? (
            <DirectMediaImage
              src={listing.cover_url}
              alt={listing.title}
              sizes="(min-width:1280px) 390px, (min-width:768px) 46vw, 92vw"
              className="listing-card-image"
              priority={priority}
            />
          ) : (
            <div className="listing-card-empty">Hakuna picha</div>
          )}
          <div className="listing-card-shade" />
          <div className="listing-card-badges">
            <span>{listing.category_name}</span>
            {listing.featured ? <span>Featured</span> : null}
          </div>
          <span className="listing-card-price">
            TZS {listing.price_amount} / {listing.price_period}
          </span>
          <div className="listing-card-copy">
            <h3>{listing.title}</h3>
            <p>{listing.public_location_label}</p>
          </div>
        </div>
        <p className="listing-card-link">
          Tazama mali <span aria-hidden="true">→</span>
        </p>
      </Link>
      <ListingActions
        listingId={listing.listing_id}
        bookingHref={
          canBook ? `/listing/${listing.listing_id}#booking` : undefined
        }
      />
    </article>
  );
}
