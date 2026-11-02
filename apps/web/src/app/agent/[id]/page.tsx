import { UiText } from "@/components/ui-text";
import { pageMetadata, isPublicId } from "@/lib/seo";
import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";
import { StatusPill } from "@/components/status-pill";
import { fetchPublicAgentProfile } from "@/lib/supabase-public";

export async function generateMetadata({ params }: { params: Promise<{ id: string }> }): Promise<Metadata> {
  const { id } = await params;
  if (!isPublicId(id)) notFound();
  const profile = await fetchPublicAgentProfile(id);
  if (!profile) notFound();
  return pageMetadata(String(profile.display_name ?? profile.business_name), `${String(profile.business_name ?? "Wakala wa KODIMALI")} - ${String(profile.location_label ?? "Tanzania")}. Angalia wasifu na shughuli za wakala kwenye KODIMALI.`, `/agent/${id}`);
}

export default async function PublicAgentPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!isPublicId(id)) notFound();
  const profile = await fetchPublicAgentProfile(id);
  if (!profile) notFound();
  const trust = (profile.trust ?? {}) as Record<string, unknown>;
  const metrics: Array<[string, string | number]> = [
    ["Response time", trust.response_minutes ? `${trust.response_minutes} minutes` : "Building history"],
    ["Response rate", `${trust.response_rate ?? 0}%`],
    ["Completed requests", String(trust.completed ?? 0)],
    ["Customer rating", `${trust.rating ?? 0} / 5 (${trust.reviews ?? 0})`],
    ["Active listings", String(profile.active_listing_count ?? 0)],
    ["Account age", `${trust.account_age_days ?? 0} days`],
  ];
  return <PageShell className="pb-20"><PageHero preserveTitle eyebrow="Verified agent" title={String(profile.display_name ?? profile.business_name ?? "KODIMALI agent")} description={`${String(profile.business_name ?? "Independent agent")} · ${String(profile.location_label ?? "Tanzania")}`} aside={<div><StatusPill label="Identity verified" tone="active" /><p className="mt-4 text-sm text-white/75"><UiText text={"Trust indicators are calculated from real KODIMALI activity."} /></p></div>} />
    <section className="grid gap-4 py-8 sm:grid-cols-2 lg:grid-cols-3">{metrics.map(([label, value]) => <article className="surface-card p-5" key={String(label)}><p className="eyebrow"><UiText text={label} /></p><p className="mt-3 text-2xl font-bold text-brand-ink">{String(value)}</p></article>)}</section>
    <section className="soft-panel p-6"><h2 className="font-heading text-2xl font-semibold"><UiText text={"Safety note"} /></h2><p className="section-copy mt-3"><UiText text={"Use the contact and viewing tools on an active listing. Never share a mobile-money PIN or pay a rent deposit before verifying the property and agreement."} /></p></section>
  </PageShell>;
}
