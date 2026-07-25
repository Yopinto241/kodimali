import { CustomerRequestWorkspace } from "@/components/customer-request-workspace";
import { PageShell } from "@/components/page-shell";

export default async function CustomerRequestPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  return (
    <PageShell className="pb-20">
      <CustomerRequestWorkspace bookingRequestId={id} />
    </PageShell>
  );
}
