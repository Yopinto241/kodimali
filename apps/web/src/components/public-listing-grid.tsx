import { GoogleAdSlot } from "@/components/google-ad-slot";
import { PublicListingCard } from "@/components/public-listing-card";

type Listing = {
  listing_id: string;
};

export function PublicListingGrid({
  listings,
  adSlot,
  clientId,
  slotId,
}: {
  listings: Listing[];
  adSlot: "home" | "category" | "detail";
  clientId: string;
  slotId: string;
}) {
  if (listings.length === 0) {
    return (
      <div className="surface-card mt-8 rounded-[20px] p-6 sm:p-8">
        <p className="eyebrow">Nothing yet</p>
        <h2 className="mt-3 font-heading text-2xl font-semibold text-brand-ink">
          Hakuna listings kwenye sehemu hii kwa sasa.
        </h2>
        <p className="section-copy mt-3 text-base">
          Jaribu category nyingine, rudi baadaye, au tumia home page kuona mali
          mpya zinazopatikana.
        </p>
      </div>
    );
  }

  const items: React.ReactNode[] = [];

  listings.forEach((listing, index) => {
    items.push(
      <PublicListingCard key={listing.listing_id} listing={listing as never} />,
    );

    if ((index + 1) % 8 === 0 && index < listings.length - 1) {
      items.push(
        <div key={`ad-${listing.listing_id}`} className="md:col-span-2">
          <GoogleAdSlot slot={adSlot} clientId={clientId} slotId={slotId} />
        </div>,
      );
    }
  });

  return <div className="mt-8 grid gap-6 md:grid-cols-2">{items}</div>;
}
