import { fetchPromotions } from "@/lib/supabase-public";
import { UiNav, UiText } from "@/components/ui-text";
import { PageShell } from "@/components/page-shell";
import { SimpleEventsListings } from "@/components/simple-events-listings";
import { fetchEventCatalog, fetchEventCategories } from "@/lib/events-public";
import { catalogMetadata, type SearchParams } from "@/lib/seo";
import Link from "next/link";
export async function generateMetadata({ searchParams }: { searchParams: Promise<SearchParams> }) {
  return catalogMetadata("Sherehe na Matukio Tanzania", "Kodisha vifaa vya sherehe, pata wataalamu wa matukio na panga tukio lako kupitia KODIMALI. Linganisha huduma na tuma ombi.", "/events", await searchParams);
}
export default async function EventsPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const kind = (await searchParams).kind === "service" ? "service" : "equipment";
  // A catalog outage is a retryable server error, never a misleading empty indexable page.
  const [initialRows, initialCategories, promotions] = await Promise.all([fetchEventCatalog(kind), fetchEventCategories(),fetchPromotions({surface:"website",placement:"category_page",categorySlug:"events"})]);
  return <PageShell>
    <SimpleEventsListings initialPromotions={promotions as never} initialMode={kind} initialRows={initialRows} initialCategories={initialCategories} />
    <noscript><UiNav aria-label="Huduma za sherehe"><Link href="/events"><UiText text={"Vifaa vya sherehe"} /></Link> | <Link href="/events?kind=service"><UiText text={"Wataalamu wa sherehe"} /></Link></UiNav></noscript>
  </PageShell>;
}
