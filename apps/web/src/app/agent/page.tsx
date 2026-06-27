import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";

export default function AgentPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="Migration note"
        title="Agent operations now live in the Manage App."
        description="Design ya mwisho inaunganisha kazi za agent na admin ndani ya management surface moja yenye routing ya role baada ya login."
      />
    </PageShell>
  );
}
