import type { Metadata } from "next";
import { ComparisonWorkspace } from "@/components/comparison-workspace";
import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";

export const metadata: Metadata = { title: "Compare listings | KODIMALI", description: "Compare KODIMALI listing prices, locations and features side by side." };

export default function ComparePage() {
  return <PageShell className="pb-20"><PageHero eyebrow="Decision tools" title="Compare listings clearly" description="Review price, location, availability and category-specific details before contacting an agent." /><ComparisonWorkspace /></PageShell>;
}
