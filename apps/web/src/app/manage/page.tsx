import type { Metadata } from "next";
import { ManagePortal } from "@/components/manage-portal";

export const metadata: Metadata = {
  title: "Manage KODIMALI",
  description: "Secure online workspace for KODIMALI agents and administrators.",
};

export default function ManagePage() {
  return <ManagePortal />;
}
