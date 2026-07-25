import type { Metadata } from "next";
import { ContentSection } from "@/components/content-section";
import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";

export const metadata: Metadata = {
  title: "Terms of use | KODIMALI",
  description: "Core marketplace, listing, request, agent, and payment terms for KODIMALI.",
};

export default function TermsPage() {
  return (
    <PageShell className="space-y-6 pb-20">
      <PageHero eyebrow="Terms of use" title="Clear responsibilities for a safer marketplace." description="These operating terms summarize how customers, agents, and administrators should use KODIMALI." />
      <ContentSection title="Marketplace role">
        <p>KODIMALI provides rental discovery, request routing, contact access, and management tools. Unless expressly stated for a specific transaction, KODIMALI is not the property owner, landlord, vehicle owner, or party to the rental agreement.</p>
      </ContentSection>
      <ContentSection title="Listings and requests">
        <p>Agents must publish accurate, authorized, and currently available listings. Customers must submit truthful contact and booking information. A request does not by itself reserve an asset or guarantee a rental.</p>
      </ContentSection>
      <ContentSection title="Payments and moderation">
        <p>The amount and purpose shown before confirmation control each KODIMALI payment. Contact-access payments do not constitute rent or a deposit. KODIMALI may review, restrict, suspend, or remove accounts and content to protect users and the platform.</p>
      </ContentSection>
    </PageShell>
  );
}
