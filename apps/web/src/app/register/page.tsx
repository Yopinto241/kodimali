import type { Metadata } from "next";
import Link from "next/link";

import { CustomerAccountPortal } from "@/components/customer-account-portal";
import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";

export const metadata: Metadata = { title: "Jisajili" };

export default function RegisterPage() {
  return (
    <PageShell className="auth-page space-y-6 pb-20">
      <PageHero
        eyebrow="Akaunti ya mteja"
        title="Fungua akaunti ya KODIMALI"
        description="Jisajili ili kutoa taarifa za mali kwa faragha, kufuatilia booking na kuona zawadi unazostahili."
        actions={<Link href="/login" className="btn btn-outline">Tayari una akaunti? Ingia</Link>}
      />
      <CustomerAccountPortal initialMode="register" />
    </PageShell>
  );
}
