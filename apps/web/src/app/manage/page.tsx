import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";

export default function ManagePage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="Manage app"
        title="One management surface for agents and admins."
        description="Baada ya login, mfumo unafungua dashboard sahihi kwa role ya mtumiaji. Hapo ndipo shughuli za listings, media, requests, approvals, na moderation zinafanyika."
      />
    </PageShell>
  );
}
