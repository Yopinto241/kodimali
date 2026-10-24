import type { Metadata } from "next";
import { AgentRegistrationForm } from "@/components/agent-registration-form";
import { PageShell } from "@/components/page-shell";
import { fetchCategories, fetchCountryId, fetchLocations } from "@/lib/supabase-public";

export const metadata: Metadata = { title: "Agent Registration" };

export default async function AgentRegistrationPage({ searchParams }: { searchParams: Promise<{ category?: string }> }) {
  const requested = (await searchParams).category;
  const countryId = await fetchCountryId();
  const [categories, regions] = await Promise.all([
    fetchCategories(),
    countryId ? fetchLocations({ locationType: "region", parentId: countryId }) : Promise.resolve([]),
  ]);
  const options = categories.map((row) => ({ id: row.id, name: row.name, slug: row.slug }));
  const initialCategoryId = options.find((row) => row.slug === requested)?.id ?? "";
  return <PageShell className="pb-20"><AgentRegistrationForm categories={options} regions={regions.map((row: { id: string; name: string }) => ({ id: row.id, name: row.name }))} initialCategoryId={initialCategoryId} /></PageShell>;
}
