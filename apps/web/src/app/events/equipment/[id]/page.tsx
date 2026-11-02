import { PublicEventPage, eventMetadata } from "@/components/public-event-page";
export async function generateMetadata({ params }: { params: Promise<{ id: string }> }) { return eventMetadata("equipment", (await params).id); }
export default async function EventEquipmentPage({ params }: { params: Promise<{ id: string }> }) { return <PublicEventPage kind="equipment" id={(await params).id} />; }
