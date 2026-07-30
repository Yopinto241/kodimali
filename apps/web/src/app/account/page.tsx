import Link from "next/link";
import { ContentSection } from "@/components/content-section";
import { CustomerAccountPortal } from "@/components/customer-account-portal";
import { CustomerGrowthTools } from "@/components/customer-growth-tools";
import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";

export default function AccountPage() {
  return (
    <PageShell className="space-y-6 pb-20">
      <PageHero
        eyebrow="Customer access"
        title="Browse as a guest or use an account for the full journey."
        description="Guest requests continue to work. A customer account adds synchronized saved listings, request tracking, agent chat, viewing appointments, and verified reviews in the customer app."
        actions={<><Link href="/listings" className="btn btn-success">Browse listings</Link><Link href="/manage" className="btn btn-outline">Agent registration</Link></>}
      />
      <CustomerAccountPortal />
      <CustomerGrowthTools />
      <ContentSection title="Your request stays with the correct agent">
        <p>When you request a listing, KODIMALI records the agent assigned to that listing. Status updates and conversation access remain tied to that request, so another agent cannot take it silently.</p>
      </ContentSection>
      <ContentSection title="Guest access remains available">
        <p>You do not need an account to browse or submit the existing name-and-phone request. Sign in only when you want cross-device history, saved listings, chat, appointments, or review eligibility.</p>
      </ContentSection>
    </PageShell>
  );
}
