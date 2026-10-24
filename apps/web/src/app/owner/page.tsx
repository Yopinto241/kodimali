import type { Metadata } from "next";
import { OwnerPortal } from "@/components/owner-portal";
import { PageShell } from "@/components/page-shell";

export const metadata: Metadata = { title: "Owner Portal", description: "Manage verified rental assets, bookings, tenants and statements." };

export default async function OwnerPage({ searchParams }: { searchParams: Promise<{ type?: string }> }) {
  const initialType = (await searchParams).type ?? "individual";
  return <PageShell className="pb-20"><OwnerPortal initialType={initialType} /></PageShell>;
}
