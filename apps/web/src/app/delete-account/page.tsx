import { UiText } from "@/components/ui-text";
import { pageMetadata } from "@/lib/seo";
import type { Metadata } from "next";
import { AccountDeletionForm } from "@/components/account-deletion-form";
import { ContentSection } from "@/components/content-section";
import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";

export const metadata: Metadata = pageMetadata('Futa Akaunti ya KODIMALI', 'Jinsi ya kuomba kufutwa kwa akaunti ya KODIMALI na taarifa zako, na taarifa zinazohitajika kubaki kwa mujibu wa masharti.', "/delete-account");

export default function DeleteAccountPage() {
  const message = encodeURIComponent(
    "Habari KODIMALI, naomba kufuta account yangu. Jina: ____ Namba/email ya account: ____ Role: customer/agent/admin.",
  );
  return (
    <PageShell className="space-y-6 pb-20">
      <PageHero
        eyebrow="Account controls"
        title="Request account and associated-data deletion."
        description="Use the in-app Profile option when available, or submit the request below from the phone connected to your account."
        actions={<a className="btn btn-success" href={`https://wa.me/255684684972?text=${message}`}><UiText text={"Request through WhatsApp"} /></a>}
      />
      <ContentSection title="What happens next">
        <p><UiText text={"Support verifies account ownership before deletion. Never send your password, PIN, or one-time login code."} /></p>
        <p><UiText text={"Public profile data and access credentials will be removed or anonymized where applicable. Some payment, fraud-prevention, dispute, audit, or legal records may be retained for the required period and access restricted."} /></p>
      </ContentSection>
      <ContentSection title="Submit a verified customer request">
        <AccountDeletionForm />
      </ContentSection>
    </PageShell>
  );
}
