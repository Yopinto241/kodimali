import type { Metadata } from "next";
export const metadata: Metadata = { robots: { index: false, follow: true }, alternates: { canonical: null } };
import { ManagePortal } from "@/components/manage-portal";

export default function AgentPage() {
  return <ManagePortal preferredRole="agent" />;
}
