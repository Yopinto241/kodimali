import Link from "next/link";
import { PublicListingCard } from "@/components/public-listing-card";

type Category = { id: string; slug: string; name: string };
type Listing = { listing_id: string; category_slug: string };

export function CategoryListingRails({ categories, listings }: { categories: Category[]; listings: Listing[] }) {
  return <section className="listing-rails space-y-14">{categories.map((category) => {
    const rows = listings.filter((listing) => listing.category_slug === category.slug);
    if (rows.length === 0) return null;
    return <section key={category.id}><div className="flex items-end justify-between gap-4"><h2 className="font-heading text-3xl font-semibold tracking-tight">{category.name}</h2><Link href={`/category/${category.slug}`} className="text-sm font-bold text-brand-teal">Tazama zote →</Link></div><div className="-mx-4 mt-6 flex snap-x snap-mandatory gap-5 overflow-x-auto px-4 pb-6 [scrollbar-width:thin] sm:-mx-6 sm:px-6">{rows.map((listing, index) => <div className="h-[390px] w-[86vw] max-w-[390px] shrink-0 snap-start" key={listing.listing_id}><PublicListingCard listing={listing as never} priority={index === 0} /></div>)}</div></section>;
  })}</section>;
}
