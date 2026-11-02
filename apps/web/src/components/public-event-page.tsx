import { notFound } from "next/navigation";
import { EventIndividualDetail } from "@/components/event-individual-detail";
import { PageShell } from "@/components/page-shell";
import { StructuredData } from "@/components/structured-data";
import { fetchPublicEventDetail, type EventKind } from "@/lib/events-public";
import { breadcrumbs, pageMetadata, serviceSchema, summary } from "@/lib/seo";

export async function eventMetadata(kind: EventKind, id: string) {
  const result = await fetchPublicEventDetail(kind, id);
  if (!result) notFound();
  const title = String(result.row.name ?? result.row.title);
  return pageMetadata(title, summary(result.row.description, `${title}. Angalia maelezo na utume ombi la huduma za sherehe kupitia KODIMALI.`), `/events/${kind}/${id}`, result.images[0]);
}

export async function PublicEventPage({ kind, id }: { kind: EventKind; id: string }) {
  const result = await fetchPublicEventDetail(kind, id);
  if (!result) notFound();
  const { row, images } = result;
  const title = String(row.name ?? row.title);
  const path = `/events/${kind}/${id}`;
  return <PageShell>
    <StructuredData data={[
      breadcrumbs([["Nyumbani", "/"], ["Sherehe na Matukio", "/events"], [title, path]]),
      serviceSchema({ title, path, description: typeof row.description === "string" ? row.description : undefined, location: typeof row.public_location_label === "string" ? row.public_location_label : undefined, price: row.pricing_mode === "custom_quote" ? null : row.price_amount_tzs, period: typeof row.price_unit === "string" ? row.price_unit : undefined, images }),
    ]} />
    <EventIndividualDetail kind={kind} id={id} initialRow={row} initialImages={images} />
  </PageShell>;
}
