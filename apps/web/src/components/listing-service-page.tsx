import { UiNav, UiText } from "@/components/ui-text";
import Link from "next/link";
import { cookies } from "next/headers";
import { notFound } from "next/navigation";
import { AgentContactCard } from "@/components/agent-contact-card";
import { GuestRequestForm } from "@/components/guest-request-form";
import { ListingChatCard } from "@/components/listing-chat-card";
import { PageShell } from "@/components/page-shell";
import { fetchListingDetail, fetchListingBookingCapability } from "@/lib/supabase-public";

export async function ListingServicePage({ id, service }: { id: string; service: "contact" | "chat" | "book" }) {
  const sw = (await cookies()).get("kodimali_language")?.value !== "en";
  const listing = await fetchListingDetail(id);
  if (!listing) notFound();
  const booking = await fetchListingBookingCapability(id);
  const attributes = (listing.listing_attributes ?? {}) as Record<string, unknown>;
  const services = listing.asset_categories?.slug === "apartment" ? [
    { key: "wifi_available", label: "WiFi" }, { key: "food_available", label: "Food" },
    { key: "transport_available", label: "Transport" }, { key: "cleaning_available", label: "Cleaning" },
    { key: "laundry_available", label: "Laundry" },
  ].filter((item) => attributes[item.key] === true) : [];
  const actions = [
    { key: "contact", label: sw ? "Mawasiliano" : "Contact" },
    { key: "chat", label: sw ? "Zungumza hapa" : "Chat here" },
    { key: "book", label: sw ? "Weka nafasi" : "Booking" },
  ].filter(action => action.key !== "book" || booking.effective_mode !== "not_bookable");
  return <PageShell className="pb-20"><div className="mx-auto max-w-3xl space-y-6">
    <Link href={`/listing/${id}`} className="inline-flex font-semibold text-brand-navy">&larr; <UiText text={sw ? "Rudi kwenye maelezo ya mali" : "Back to listing details"} /></Link>
    <header className="surface-card rounded-[20px] p-5 sm:p-7">
      <p className="eyebrow"><UiText text={actions.find((action) => action.key === service)?.label} /></p>
      <h1 className="mt-3 font-heading text-3xl font-semibold text-brand-ink">{listing.title}</h1>
      <p className="mt-2 text-sm text-muted">{listing.public_location_label}</p>
      <UiNav aria-label={sw ? "Huduma za listing" : "Listing services"} className="mt-5 flex flex-wrap gap-2">
        {actions.map((action) => <Link key={action.key} href={`/listing/${id}/${action.key}`} aria-current={action.key === service ? "page" : undefined} className={`btn ${action.key === service ? "btn-success" : "btn-outline"}`}><UiText text={action.label} /></Link>)}
      </UiNav>
    </header>
    {service === "contact" ? <AgentContactCard listingId={id} agentSummary={{...listing.agent_summary,phone_number:null} as never} /> : null}
    {service === "chat" ? <ListingChatCard listingId={id} /> : null}
    {service === "book" && booking ? <GuestRequestForm listingId={id} listingTitle={listing.title} categorySlug={listing.asset_categories?.slug} availableServices={services} bookingMode={booking.effective_mode} /> : null}
  </div></PageShell>;
}
