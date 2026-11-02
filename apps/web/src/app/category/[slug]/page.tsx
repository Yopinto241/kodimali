import { SaveSearchButton } from "@/components/save-search-button";
import { UiText } from "@/components/ui-text";
import { CatalogFilters } from "@/components/catalog-filters";
import { catalogLocation } from "@/lib/catalog-location";
import { optionalNumber } from "@/lib/listing-search";
import { notFound } from "next/navigation";
import { catalogMetadata, type SearchParams } from "@/lib/seo";
import Link from "next/link";
import { cookies } from "next/headers";
import { GoogleAdSlot } from "@/components/google-ad-slot";
import { PageShell } from "@/components/page-shell";
import { PublicListingGrid } from "@/components/public-listing-grid";
import { fetchCategories, fetchCountryId, fetchLocations, fetchPromotions, fetchPublicListings } from "@/lib/supabase-public";

const categoryCopy: Record<string, string> = {
  house: "Nyumba za kupanga Tanzania", apartment: "Apartments za kukodisha Tanzania", car: "Magari ya kukodisha Tanzania", motorcycle: "Pikipiki za kukodisha Tanzania", office: "Ofisi za kukodisha Tanzania", "meeting-hall": "Kumbi za mikutano Tanzania", "ceremony-hall": "Kumbi za sherehe Tanzania", equipment: "Vifaa vya kukodisha Tanzania", farms: "Mashamba ya kukodisha Tanzania", "other-asset": "Mali nyingine za kukodisha Tanzania",
};
export async function generateMetadata({ params, searchParams }: { params: Promise<{ slug: string }>; searchParams: Promise<SearchParams> }) {
  const { slug } = await params;
  const category = (await fetchCategories()).find(item => item.slug === slug);
  if (!category) notFound();
  const title = categoryCopy[slug] ?? `${category.name} Tanzania`;
  return catalogMetadata(title, category.description || `${title}. Linganisha mali, maeneo na bei, kisha tuma ombi kupitia KODIMALI.`, `/category/${slug}`, await searchParams);
}

export const revalidate = 120;
const pageSize = 20;

function buildPageHref(slug: string, params: Record<string, string | string[] | undefined>, nextPage: number) {
  const query = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (Array.isArray(value)) value.forEach((item) => query.append(key, item));
    else if (value) query.set(key, value);
  }
  if (nextPage <= 1) query.delete("page"); else query.set("page", String(nextPage));
  return query.size ? `/category/${slug}?${query}` : `/category/${slug}`;
}

export default async function CategoryPage({ params, searchParams }: { params: Promise<{ slug: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sw = (await cookies()).get("kodimali_language")?.value !== "en";
  const { slug } = await params;
  const query = await searchParams;
  const value = (key: string) => typeof query[key] === "string" ? query[key] as string : undefined;
  const currentPage = Math.max(1, Number.parseInt(value("page") ?? "1", 10) || 1);
  const { regionId, districtId, wardId, areaId } = await catalogLocation(query);
  const searchText = value("q")?.trim();
  const minPrice = optionalNumber(query.minPrice, true), maxPrice = optionalNumber(query.maxPrice, true);
  const pricePeriod = value("pricePeriod");
  const requestedSort = value("sort") ?? "recommended";
  const sort = (["recommended", "newest", "price_low", "price_high"] as const).includes(requestedSort as never) ? requestedSort as "recommended" | "newest" | "price_low" | "price_high" : "recommended";
  const countryId = await fetchCountryId();
  const [categories, listings, promotions, regions, selectedDistricts, selectedWards, selectedAreas] = await Promise.all([
    fetchCategories(),
    fetchPublicListings({ categorySlug: slug, searchText, regionId, districtId, wardId, areaId, limit: pageSize, page: currentPage - 1, sessionSeed: slug, minPrice, maxPrice, pricePeriod, sort }),
    fetchPromotions({ surface: "website", placement: "category_page", categorySlug: slug, regionId, districtId, wardId, areaId }),
    countryId ? fetchLocations({ locationType: "region", parentId: countryId }) : Promise.resolve([]),
    regionId ? fetchLocations({ locationType: "district", parentId: regionId }) : Promise.resolve([]),
    districtId ? fetchLocations({ locationType: "ward", parentId: districtId }) : Promise.resolve([]),
    wardId ? fetchLocations({ locationType: "area", parentId: wardId }) : Promise.resolve([]),
  ]);
  const category = categories.find((item: { slug: string }) => item.slug === slug);
  if (!category) notFound();
  const totalCount = Number(listings[0]?.total_count ?? listings.length);

  return <PageShell className="pb-20">
    <CatalogFilters path={`/category/${slug}`} title={category.name} sw={sw} totalCount={totalCount} regions={regions} selectedDistricts={selectedDistricts} selectedWards={selectedWards} selectedAreas={selectedAreas} regionId={regionId} districtId={districtId} wardId={wardId} areaId={areaId} searchText={searchText} minPrice={minPrice} maxPrice={maxPrice} pricePeriod={pricePeriod} sort={sort} />
    <div className="mt-4"><SaveSearchButton filters={{ q: searchText ?? "", category: slug, regionId: regionId ?? "", districtId: districtId ?? "", wardId: wardId ?? "", areaId: areaId ?? "", minPrice: minPrice == null ? "" : String(minPrice), maxPrice: maxPrice == null ? "" : String(maxPrice), pricePeriod: pricePeriod ?? "", sort }} /></div>
    <PublicListingGrid promotions={promotions as never} listings={listings as Array<{ listing_id: string }> } adSlot="category" clientId={process.env.ADSENSE_CLIENT_ID ?? ""} slotId={process.env.ADSENSE_SLOT_CATEGORY ?? ""} />
    <section className="mt-8 flex flex-wrap items-center justify-between gap-3"><p className="section-copy text-sm"><UiText text={sw ? "Ukurasa" : "Page"} /> {currentPage}</p><div className="flex flex-wrap gap-3">{currentPage > 1 ? <Link href={buildPageHref(slug, query, currentPage - 1)} className="btn btn-outline"><UiText text={sw ? "Iliyopita" : "Previous"} /></Link> : null}{listings.length === pageSize ? <Link href={buildPageHref(slug, query, currentPage + 1)} className="btn btn-primary"><UiText text={sw ? "Inayofuata" : "Next"} /></Link> : null}</div></section>
    <GoogleAdSlot slot="category" clientId={process.env.ADSENSE_CLIENT_ID ?? ""} slotId={process.env.ADSENSE_SLOT_CATEGORY ?? ""} />
  </PageShell>;
}
