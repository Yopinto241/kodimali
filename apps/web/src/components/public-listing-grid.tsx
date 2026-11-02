import { PromotionCard, PromotionStrip, type Promotion } from "@/components/promotion-strip";
import { UiText } from "@/components/ui-text";
import { GoogleAdSlot } from "@/components/google-ad-slot";
import { PublicListingCard } from "@/components/public-listing-card";
import { LISTINGS_PER_SPONSORED_CARD, sponsoredLayout } from "@/lib/sponsored-layout";

type Listing = {
  listing_id: string;
};

export function PublicListingGrid({
  listings,
  adSlot,
  clientId,
  slotId,
  promotions = [],
}: {
  listings: Listing[];
  adSlot: "home" | "category" | "detail";
  clientId: string;
  slotId: string;
  promotions?: Promotion[];
}) {
  if (listings.length === 0) {
    return (
      <><div className="surface-card mt-8 rounded-[20px] p-6 sm:p-8">
        <p className="eyebrow"><UiText text={"No matching listings"} /></p>
        <h2 className="mt-3 font-heading text-2xl font-semibold text-brand-ink"><UiText text={"No listings match these filters."} /></h2>
        <p className="section-copy mt-3 text-base"><UiText text={"Try another location or remove a filter to see more listings."} /></p>
      </div><PromotionStrip promotions={promotions} /></>
    );
  }

  const items: React.ReactNode[] = [];
  const { inline, remaining } = sponsoredLayout(promotions, listings.length);

  let promotionIndex = 0;
  listings.forEach((listing, index) => {
    items.push(
      <PublicListingCard key={listing.listing_id} listing={listing as never} priority={index < 2} />,
    );

    if ((index + 1) % LISTINGS_PER_SPONSORED_CARD === 0 && promotionIndex < inline.length) {
      const promotion = inline[promotionIndex++];
      items.push(<PromotionCard key={`promotion-${promotion.promotion_id}`} promotion={promotion} />);
    }

    else if (clientId && slotId && (index + 1) % LISTINGS_PER_SPONSORED_CARD === 0 && index < listings.length - 1) {
      items.push(
        <div key={`ad-${listing.listing_id}`} className="md:col-span-2">
          <GoogleAdSlot slot={adSlot} clientId={clientId} slotId={slotId} />
        </div>,
      );
    }
  });

  return <><div className="mt-8 grid gap-6 md:grid-cols-2">{items}</div><PromotionStrip promotions={remaining} /></>;
}
