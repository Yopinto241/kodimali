import type { Metadata } from "next";
import Link from "next/link";

import { CustomerAccountPortal } from "@/components/customer-account-portal";
import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";

export const metadata: Metadata = { title: "Ingia" };

export default function LoginPage() {
  return (
    <PageShell className="auth-page space-y-6 pb-20">
      <PageHero
        eyebrow="Akaunti ya mteja"
        title="Ingia KODIMALI"
        description="Fuatilia taarifa ulizotoa, miadi, booking na historia yako kwa usalama."
        actions={<Link href="/register" className="btn btn-outline">Huna akaunti? Jisajili</Link>}
      />
      <CustomerAccountPortal initialMode="login" />
    </PageShell>
  );
}
