import { BackNavButton } from "@/components/back-nav-button";
import { EventPlanBuilder } from "@/components/event-plan-builder";
import { PageShell } from "@/components/page-shell";

export const metadata = { title: "Panga Tukio | KODIMALI" };

export default function PlanEventPage() {
  return (
    <PageShell>
      <BackNavButton fallbackHref="/events" />
      <EventPlanBuilder />
    </PageShell>
  );
}
