import Link from "next/link";
import type { Metadata } from "next";
import { ManagePortal } from "@/components/manage-portal";

export const metadata: Metadata = {
  title: "Manage KODIMALI",
  description: "Secure online workspace for KODIMALI agents and administrators.",
};

export default async function ManagePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const query = await searchParams;
  return <><div className="app-shell py-3"><Link className="btn btn-outline" href="/manage/lodges">Lodge workspace</Link></div><ManagePortal preferredRole={query.workspace === 'agent' ? 'agent' : undefined} /></>;
}
