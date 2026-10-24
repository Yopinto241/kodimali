import type { Metadata } from "next";
import Link from "next/link";

import { CustomerAccountPortal } from "@/components/customer-account-portal";
import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";

export const metadata: Metadata = { title: "Register as an owner" };

export default async function OwnerRegistrationPage({ searchParams }: { searchParams: Promise<{ type?: string }> }) {
  const requestedType = (await searchParams).type;
  const destination = requestedType === "authorized_manager" || requestedType === "venue_owner"
    ? `/owner?type=${requestedType}`
    : "/owner";
  return (
    <PageShell className="space-y-6 pb-20">
      <PageHero
        eyebrow="Owner registration"
        title="Open an owner account"
        description="Create your login first, then submit your ownership or management details for verification. Approval is required before the owner workspace is activated."
        actions={<Link href="/manage" className="btn btn-outline">Already registered? Sign in</Link>}
      />
      <CustomerAccountPortal initialMode="register" destination={destination} accountKind="owner" />
    </PageShell>
  );
}
