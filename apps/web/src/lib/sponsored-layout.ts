export const LISTINGS_PER_SPONSORED_CARD = 3;

/** One slot per three organic listings, with organic content after each slot. */
export function sponsoredLayout<T extends { promotion_id: string }>(promotions: T[], listingCount: number) {
  const unique = [...new Map(promotions.map((promotion) => [promotion.promotion_id, promotion])).values()];
  const slots = Math.max(0, Math.floor((listingCount - 1) / LISTINGS_PER_SPONSORED_CARD));
  return { inline: unique.slice(0, slots), remaining: unique.slice(slots) };
}
