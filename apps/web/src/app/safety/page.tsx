import { UiText } from "@/components/ui-text";
import { pageMetadata } from "@/lib/seo";
import type { Metadata } from "next";
import { ContentSection } from "@/components/content-section";
import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";

export const metadata: Metadata = pageMetadata('Usalama wa Kukodisha', 'Jinsi ya kukagua mali, kulinda malipo na kuripoti shughuli zinazotia shaka kupitia KODIMALI.', "/safety");

export default function SafetyPage() {
  return (
    <PageShell className="space-y-6 pb-20">
      <PageHero
        eyebrow="Trust and safety"
        title="Inspect first. Verify the agent. Protect every payment."
        description="KODIMALI helps customers discover rentals and connect with agents, but customers should verify the asset and agreement before paying a rent deposit."
      />
      <ContentSection title="Before you pay">
        <p><UiText text={"Visit or independently verify the asset, price, availability, ownership or authority to rent, and written agreement."} /></p>
        <p><UiText text={"Never share a mobile-money PIN, password, one-time code, or card security code with an agent or KODIMALI support."} /></p>
        <p><UiText text={"Use the payment flow shown inside KODIMALI only for the service described on that screen. A contact-unlock payment is not a rent deposit."} /></p>
      </ContentSection>
      <ContentSection title="Report suspicious activity">
        <p><UiText text={"Keep the listing link, request reference, phone number, payment reference, and screenshots."} /></p>
        <p><UiText text={"Contact support through the official phone or WhatsApp details in the footer. For immediate financial loss, also contact the payment provider and relevant authorities."} /></p>
      </ContentSection>
    </PageShell>
  );
}
