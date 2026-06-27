import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";

export default function AccountPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="Guest browsing"
        title="KODIMALI website haihitaji customer account."
        description="Tumia home page, categories, listings, na detail page kutuma ombi la jina na namba ya simu moja kwa moja kwa wakala."
      />
    </PageShell>
  );
}
