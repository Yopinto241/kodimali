import { EventIndividualDetail } from "@/components/event-individual-detail";
import { PageShell } from "@/components/page-shell";

export default async function EventEquipmentPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <PageShell><EventIndividualDetail kind="equipment" id={id} /></PageShell>;
}
