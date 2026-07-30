import type { Metadata } from "next";
import Link from "next/link";
import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";

export const metadata: Metadata = { title: "Advertise with KODIMALI", description: "Reach property customers through sponsored campaigns and featured KODIMALI listings." };
export default function AdvertisePage() {
  const products = [
    ["Sponsored campaigns", "Custom image or video advertising targeted by placement, audience, date and location."],
    ["Featured listings", "Promote a real listing on the homepage, category results or top of search."],
    ["Agent subscriptions", "Unlock listing capacity, analytics, priority and business team capabilities."],
  ];
  return <PageShell className="pb-20"><PageHero eyebrow="Grow with KODIMALI" title="Reach customers when they are ready to act" description="KODIMALI advertising is clearly labelled, measurable and designed around useful marketplace discovery." actions={<Link href="/manage" className="btn btn-success">Open business workspace</Link>} />
    <section className="grid gap-5 py-8 md:grid-cols-3">{products.map(([title, copy]) => <article className="surface-card p-6" key={title}><h2 className="font-heading text-2xl font-semibold">{title}</h2><p className="section-copy mt-3">{copy}</p></article>)}</section>
    <section className="navy-panel p-7"><h2 className="font-heading text-3xl font-semibold">Campaign measurement included</h2><p className="mt-3 max-w-3xl text-white/75">Impressions, clicks, click-through rate, listing views and contact conversions let the business assess real results rather than relying on screenshots.</p></section>
  </PageShell>;
}
