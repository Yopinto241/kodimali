import { UiText } from "@/components/ui-text";
import type { Metadata } from "next";
import Link from "next/link";
import { PageShell } from "@/components/page-shell";
export const metadata: Metadata = { title: "Ukurasa haujapatikana", robots: { index: false, follow: true }, alternates: { canonical: null } };
export default function NotFound() {
  return <PageShell><section className="surface-card my-8 rounded-[20px] p-8"><h1><UiText text={"Ukurasa haujapatikana"} /></h1><p className="section-copy mt-3"><UiText text={"Mali au huduma hii haipatikani kwa sasa."} /></p><Link href="/listings" className="btn btn-primary mt-5"><UiText text={"Angalia mali"} /></Link></section></PageShell>;
}
