import { UiText } from "@/components/ui-text";
import { pageMetadata } from "@/lib/seo";
import type { Metadata } from "next";
import Link from "next/link";
import { ContentSection } from "@/components/content-section";
import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";

export const metadata: Metadata = pageMetadata('Faragha na Taarifa Binafsi', 'Jifunze jinsi KODIMALI inavyoshughulikia taarifa za akaunti, mali, maeneo na malipo.', "/privacy");

export default function PrivacyPage() {
  return (
    <PageShell className="space-y-6 pb-20">
      <PageHero
        eyebrow="Privacy"
        title="Your information should have a clear purpose."
        description="This summary explains the main information KODIMALI uses to operate rental discovery, requests, agent accounts, moderation, and payments."
      />
      <ContentSection title="Information we use">
        <p><UiText text={"Customer request details can include name, phone, email, requested dates, requested services, messages, account identity, and status history."} /></p>
        <p><UiText text={"Agent information can include account details, business profile, phone, location, identity-verification documents, listings, owner records, and operational activity."} /></p>
        <p><UiText text={"Payment providers return transaction references and statuses. KODIMALI should never ask for or store your mobile-money PIN."} /></p>
      </ContentSection>
      <ContentSection title="Why and how long">
        <p><UiText text={"Information is used to deliver requests, protect the marketplace, process contact access, support users, prevent fraud, and meet legal obligations. Private owner details, exact locations, and verification documents are not part of the public listing feed."} /></p>
        <p><UiText text={"Operational, security, tax, or dispute records may need to be retained after an account-deletion request. Any retained information should be limited to the required purpose."} /></p>
      </ContentSection>
      <ContentSection title="Your choices">
        <p><UiText text={"You may ask to correct or delete account information. See the "} /><Link className="font-semibold text-brand-navy underline" href="/delete-account"><UiText text={"account deletion page"} /></Link><UiText text={" for the request process."} /></p>
      </ContentSection>
    </PageShell>
  );
}
