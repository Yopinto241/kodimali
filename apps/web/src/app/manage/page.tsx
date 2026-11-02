import type { Metadata } from "next";
import { ManagePortal } from "@/components/manage-portal";

export const metadata: Metadata = {
  title: "Manage KODIMALI",
  description: "Secure online workspace for KODIMALI agents and administrators.",
};

export default async function ManagePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const query = await searchParams;
  return <ManagePortal preferredRole={query.workspace === 'agent' ? 'agent' : undefined} />;
}
