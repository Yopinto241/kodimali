import { PageShell } from "@/components/page-shell";
import { SimpleEventsListings } from "@/components/simple-events-listings";

export const metadata = {
  title: "Sherehe na Matukio | KODIMALI",
  description:
    "Kodisha vifaa, pata wataalamu na panga tukio lako kupitia KODIMALI.",
};

export default function EventsPage() {
  return (
    <PageShell>
      <SimpleEventsListings />
    </PageShell>
  );
}
