import { UiText } from "@/components/ui-text";
import { pageMetadata } from "@/lib/seo";
import type { Metadata } from "next";
import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";

export const metadata: Metadata = pageMetadata('Pakua Programu za KODIMALI', 'Pata programu za KODIMALI kwa wateja, mawakala na biashara. Angalia chaguo za upakuaji na usaidizi.', "/download");
export default function DownloadPage() {
  return <PageShell className="pb-20"><PageHero eyebrow="KODIMALI mobile" title="Keep listings, messages and appointments with you" description="The mobile apps add push notifications, synchronized activity and faster agent workflows." />
    <section className="grid gap-6 py-8 md:grid-cols-2"><article className="surface-card p-7"><p className="eyebrow"><UiText text={"Customers"} /></p><h2 className="mt-3 font-heading text-3xl font-semibold">KODIMALI Customer</h2><p className="section-copy mt-3"><UiText text={"Browse, save, compare, request, chat and receive price alerts."} /></p><p className="mt-5 rounded-xl bg-brand-amber-soft p-4 text-sm font-semibold"><UiText text={"Play Store link will appear here after the production listing is published."} /></p></article><article className="surface-card p-7"><p className="eyebrow"><UiText text={"Business"} /></p><h2 className="mt-3 font-heading text-3xl font-semibold">KODIMALI Manage</h2><p className="section-copy mt-3"><UiText text={"Manage listings, leads, campaigns, subscriptions and marketplace operations."} /></p><p className="mt-5 rounded-xl bg-brand-amber-soft p-4 text-sm font-semibold"><UiText text={"Use the secure web workspace now; the store link activates after release."} /></p></article></section>
  </PageShell>;
}
