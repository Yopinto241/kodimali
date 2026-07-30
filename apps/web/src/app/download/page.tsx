import type { Metadata } from "next";
import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";

export const metadata: Metadata = { title: "Download KODIMALI", description: "Install KODIMALI customer and business mobile apps." };
export default function DownloadPage() {
  return <PageShell className="pb-20"><PageHero eyebrow="KODIMALI mobile" title="Keep listings, messages and appointments with you" description="The mobile apps add push notifications, synchronized activity and faster agent workflows." />
    <section className="grid gap-6 py-8 md:grid-cols-2"><article className="surface-card p-7"><p className="eyebrow">Customers</p><h2 className="mt-3 font-heading text-3xl font-semibold">KODIMALI Customer</h2><p className="section-copy mt-3">Browse, save, compare, request, chat and receive price alerts.</p><p className="mt-5 rounded-xl bg-brand-amber-soft p-4 text-sm font-semibold">Play Store link will appear here after the production listing is published.</p></article><article className="surface-card p-7"><p className="eyebrow">Business</p><h2 className="mt-3 font-heading text-3xl font-semibold">KODIMALI Manage</h2><p className="section-copy mt-3">Manage listings, leads, campaigns, subscriptions and marketplace operations.</p><p className="mt-5 rounded-xl bg-brand-amber-soft p-4 text-sm font-semibold">Use the secure web workspace now; the store link activates after release.</p></article></section>
  </PageShell>;
}
