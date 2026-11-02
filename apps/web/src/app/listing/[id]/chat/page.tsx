import type { Metadata } from "next";
import { ListingServicePage } from "@/components/listing-service-page";
export const metadata: Metadata = { robots: { index: false, follow: true } };
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <ListingServicePage id={id} service="chat" />;
}
