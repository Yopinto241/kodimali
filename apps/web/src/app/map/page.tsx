import type { Metadata } from "next";
import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";
import { SafeMapSearch } from "@/components/safe-map-search";
export const metadata: Metadata = { title: "Nearby map search", description: "Use approximate location to discover nearby KODIMALI listings without exposing private property coordinates." };
export default function MapPage() { return <PageShell className="pb-20"><PageHero eyebrow="Location discovery" title="Explore nearby while protecting exact addresses" description="KODIMALI ranks public listing areas using approximate distance. Exact property coordinates are shared only through a legitimate viewing process." /><SafeMapSearch /></PageShell>; }
