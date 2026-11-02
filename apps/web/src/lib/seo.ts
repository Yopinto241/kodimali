import type { Metadata } from "next";

export const SITE_URL = "https://kodimali.com";
export const HOME_TITLE = "KODIMALI | Nyumba, Magari na Huduma za Kukodisha Tanzania";
export const HOME_DESCRIPTION = "Tafuta nyumba, apartments, magari, ofisi, kumbi, vifaa na wataalamu wa sherehe Tanzania. Gundua mali na huduma, linganisha chaguo na uweke booking kupitia KODIMALI.";
export const absoluteUrl = (path: string) => new URL(path, `${SITE_URL}/`).href;
export const isPublicId = (id: string) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id);
export const summary = (value: unknown, fallback: string) => String(value ?? "").replace(/\s+/g, " ").trim().slice(0, 170) || fallback;

export function pageMetadata(title: string, description: string, path: string, image = "/opengraph-image") : Metadata {
  const branded = title.includes("KODIMALI") ? title : `${title} | KODIMALI`;
  return {
    title: { absolute: branded }, description,
    alternates: { canonical: absoluteUrl(path) },
    openGraph: { type: "website", siteName: "KODIMALI", locale: "sw_TZ", title: branded, description, url: absoluteUrl(path), images: [{ url: absoluteUrl(image), alt: title }] },
    twitter: { card: "summary_large_image", title: branded, description, images: [absoluteUrl(image)] },
  };
}

export type SearchParams = Record<string, string | string[] | undefined>;
export function catalogMetadata(title: string, description: string, path: string, query: SearchParams): Metadata {
  // Tracking parameters do not change content. All arbitrary search/filter combinations stay out of the index.
  const filtered = Object.entries(query).some(([key, value]) => value && !["page", "utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term", "gclid", "fbclid"].includes(key));
  const rawPage = typeof query.page === "string" ? query.page : query.page === undefined ? "1" : "invalid";
  const page = /^\d+$/.test(rawPage) ? Number(rawPage) : NaN;
  const validPage = Number.isSafeInteger(page) && page > 0;
  const canonical = !filtered && validPage && page > 1 ? `${path}?page=${page}` : path;
  return { ...pageMetadata(page > 1 && validPage ? `${title} - Ukurasa ${page}` : title, description, canonical), robots: { index: !filtered && validPage, follow: true } };
}

export function breadcrumbs(items: Array<[string, string]>) {
  return { "@context": "https://schema.org", "@type": "BreadcrumbList", itemListElement: items.map(([name, path], index) => ({ "@type": "ListItem", position: index + 1, name, item: absoluteUrl(path) })) };
}

export function serviceSchema(data: { title: string; description?: string | null; path: string; location?: string | null; price?: unknown; period?: string | null; images?: string[] }) {
  const price = data.price == null || data.price === "" ? NaN : Number(data.price);
  return {
    "@context": "https://schema.org", "@type": "Service", name: data.title,
    description: data.description || undefined, url: absoluteUrl(data.path),
    areaServed: data.location || undefined, image: data.images?.length ? data.images : undefined,
    ...(Number.isFinite(price) && price >= 0 ? { offers: { "@type": "Offer", url: absoluteUrl(data.path), priceCurrency: "TZS", priceSpecification: { "@type": "UnitPriceSpecification", price, priceCurrency: "TZS", unitText: data.period || undefined } } } : {}),
  };
}
