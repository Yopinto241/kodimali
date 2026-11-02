import type { MetadataRoute } from "next";
import { fetchCategories } from "@/lib/supabase-public";
import { fetchSitemapPage } from "@/lib/sitemap-public";
import { buildPublicSitemap } from "@/lib/sitemap";

// Keep the existing /sitemap.xml MetadataRoute and flat urlset recognized by Search Console.
export const revalidate = 300;
export const dynamic = "force-dynamic";
export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  return buildPublicSitemap(await fetchCategories(), fetchSitemapPage);
}
