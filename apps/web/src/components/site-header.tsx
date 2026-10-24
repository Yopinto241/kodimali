import { PremiumNavbar } from "@/components/premium/premium-navbar";
import { fetchCategories } from "@/lib/supabase-public";

export async function SiteHeader() {
  const categories = await fetchCategories() as Array<{ id: string; slug: string; name: string }>;
  return <PremiumNavbar categories={categories} />;
}
