import "server-only";
import { unstable_cache } from "next/cache";
import { supabaseFetch } from "@/lib/supabase-public";
import { SITEMAP_PAGE_SIZE, type SitemapKind } from "@/lib/sitemap";

export const fetchSitemapPage = unstable_cache(async (kind: SitemapKind, page = 0, limit = SITEMAP_PAGE_SIZE) => {
  const value = await supabaseFetch("/rest/v1/rpc/get_public_seo_sitemap", {
    method: "POST", body: JSON.stringify({ p_kind: kind, p_offset: page * SITEMAP_PAGE_SIZE, p_limit: limit }),
  }, { revalidate: 300, tags: ["public-sitemap", "public-listings", "public-events"] });
  if (!value || !Number.isSafeInteger(value.total_count) || value.total_count < 0 || !Array.isArray(value.entries)) throw new Error("Invalid public sitemap response");
  return value as { total_count: number; entries: Array<{ id: string; updated_at: string | null }> };
}, ["approved-public-sitemap-v1"], { revalidate: 300, tags: ["public-sitemap", "public-listings", "public-events"] });
