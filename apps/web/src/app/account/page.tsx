import { CustomerAccountPortal } from "@/components/customer-account-portal";
import { CustomerGrowthTools } from "@/components/customer-growth-tools";
import { PageShell } from "@/components/page-shell";

const sections = new Set(["overview", "bookings", "chats", "invitations", "events", "activity", "settings"]);

export default async function AccountPage({ searchParams }: { searchParams: Promise<{ section?: string }> }) {
  const requested = (await searchParams).section ?? "overview";
  const section = sections.has(requested) ? requested : "overview";
  return (
    <PageShell className="account-shell space-y-6 pb-20">
      <CustomerAccountPortal section={section} />
      {section === "activity" || section === "settings" ? <div id="shughuli" className="scroll-mt-40"><CustomerGrowthTools mode={section} /></div> : null}
    </PageShell>
  );
}
