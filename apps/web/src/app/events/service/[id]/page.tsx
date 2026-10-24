import { EventIndividualDetail } from "@/components/event-individual-detail";
import { PageShell } from "@/components/page-shell";

export default async function EventServicePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <PageShell><EventIndividualDetail kind="service" id={id} /></PageShell>;
}
