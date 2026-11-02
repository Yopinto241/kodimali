import { PublicEventPage, eventMetadata } from "@/components/public-event-page";
export async function generateMetadata({ params }: { params: Promise<{ id: string }> }) { return eventMetadata("service", (await params).id); }
export default async function EventServicePage({ params }: { params: Promise<{ id: string }> }) { return <PublicEventPage kind="service" id={(await params).id} />; }
