import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";

export default function AdminPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="Migration note"
        title="Admin operations now live in the Manage App."
        description="Agent activation, listing moderation, category management, complaints, reports, na location control vinapaswa kufanyika kwenye shared Manage App, si website ya umma."
      />
    </PageShell>
  );
}
