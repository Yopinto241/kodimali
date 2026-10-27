import { CustomerAccountPortal } from "@/components/customer-account-portal";
import { CustomerGrowthTools } from "@/components/customer-growth-tools";
import { PageShell } from "@/components/page-shell";

export default function AccountPage() {
  return (
    <PageShell className="account-shell space-y-6 pb-20">
      <CustomerAccountPortal />
      <div id="shughuli" className="scroll-mt-40"><CustomerGrowthTools /></div>
    </PageShell>
  );
}
