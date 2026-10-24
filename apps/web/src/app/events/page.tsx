import { BackNavButton } from "@/components/back-nav-button";
import { EventsMarketplace } from "@/components/events-marketplace";
import { PageShell } from "@/components/page-shell";

export const metadata = {
  title: "Sherehe na Matukio | KODIMALI",
  description: "Kodisha vifaa, pata wataalamu na panga tukio lako kupitia KODIMALI.",
};

export default function EventsPage() {
  return (
    <PageShell>
      <BackNavButton />
      <EventsMarketplace />
    </PageShell>
  );
}
