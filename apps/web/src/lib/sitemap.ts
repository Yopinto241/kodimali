import { absoluteUrl, isPublicId } from "./seo.ts";

export const SITEMAP_PAGE_SIZE = 1000;
export const sitemapKinds = ["listings", "equipment", "services"] as const;
export type SitemapKind = typeof sitemapKinds[number];
export type SitemapEntry = { path: string; updatedAt?: string | null };
export const staticPaths = ["/", "/listings", "/events", "/toa-taarifa", "/safety", "/privacy", "/terms", "/delete-account", "/advertise", "/download"];
export function inventoryPath(kind: SitemapKind, id: string) {
  if (!isPublicId(id)) throw new Error("Invalid public inventory ID");
  return `${kind === "listings" ? "/listing" : `/events/${kind === "equipment" ? "equipment" : "service"}`}/${id}`;
}

export type PublicSitemapPage = { total_count: number; entries: Array<{ id: string; updated_at: string | null }> };
export async function buildPublicSitemap(categories: Array<{ slug: string }>, readPage: (kind: SitemapKind, page: number) => Promise<PublicSitemapPage>) {
  const entries: Array<{ url: string; lastModified?: string }> = [
    ...staticPaths.map(path => ({ url: absoluteUrl(path) })),
    ...categories.filter(category => category.slug !== "events").map(category => ({ url: absoluteUrl(`/category/${encodeURIComponent(category.slug)}`) })),
  ];
  for (const kind of sitemapKinds) {
    let page = 0;
    let total = 0;
    do {
      const result = await readPage(kind, page);
      total = result.total_count;
      if (!Number.isSafeInteger(total) || total < 0 || (page * SITEMAP_PAGE_SIZE < total && !result.entries.length)) throw new Error("Invalid public sitemap page");
      for (const row of result.entries) {
        if (row.updated_at && !Number.isFinite(Date.parse(row.updated_at))) throw new Error("Invalid public modification date");
        entries.push({ url: absoluteUrl(inventoryPath(kind, row.id)), ...(row.updated_at ? { lastModified: row.updated_at } : {}) });
        if (entries.length > 50000) throw new Error("Public sitemap exceeds the flat sitemap URL limit");
      }
      page++;
    } while (page * SITEMAP_PAGE_SIZE < total);
  }
  return entries;
}
