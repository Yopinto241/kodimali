import type { MetadataRoute } from "next";
import { fetchCategories, fetchPublicListings } from "@/lib/supabase-public";

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const baseUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "https://kodimali.co.tz";
  const now = new Date();
  const staticEntries: MetadataRoute.Sitemap = [
    "",
    "/listings",
    "/account",
    "/safety",
    "/privacy",
    "/terms",
    "/delete-account",
    "/manage",
  ].map((path) => ({ url: `${baseUrl}${path}`, lastModified: now }));
  try {
    const [categories, listings] = await Promise.all([
      fetchCategories(),
      fetchPublicListings({ limit: 1000, page: 0, sessionSeed: "sitemap" }),
    ]);
    return staticEntries
    .concat(categories.map((category) => ({
      url: `${baseUrl}/category/${category.slug}`,
      lastModified: now,
    })))
    .concat((listings as Array<{ listing_id?: string; id?: string }>).flatMap((listing) => {
      const id = listing.listing_id ?? listing.id;
      return id ? [{ url: `${baseUrl}/listing/${id}`, lastModified: now }] : [];
    }));
  } catch {
    // A deployment must remain buildable during a temporary Supabase outage.
    // Dynamic category and listing URLs return on the next sitemap revalidation.
    return staticEntries;
  }
}
