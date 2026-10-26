"use client";

import Link from "next/link";
import { EventsPublicCatalog } from "@/components/events-public-catalog";
import { useLanguage } from "@/components/language-provider";

export function EventsMarketplace() {
  const { language } = useLanguage();
  const sw = language === "sw";
  return (
    <div className="events-page space-y-8 pb-16 sm:space-y-10">
      <section className="events-hero owner-hero relative overflow-hidden rounded-[28px] p-6 text-white sm:p-9">
        <div className="absolute -right-20 -top-24 h-72 w-72 rounded-full bg-brand-amber/20 blur-3xl" />
        <p className="eyebrow !text-brand-amber">KODIMALI Events</p>
        <h1 className="mt-3 max-w-3xl font-heading text-4xl font-semibold sm:text-5xl">
          {sw
            ? "Vifaa na wataalamu wa sherehe."
            : "Equipment and professionals for events."}
        </h1>
        <p className="mt-4 max-w-2xl text-base text-white/75 sm:text-lg">
          {sw
            ? "Vinjari matangazo yaliyothibitishwa kama unavyotafuta nyumba, gari au ukumbi. Chagua eneo pale unapohitaji kupunguza matokeo."
            : "Browse verified listings just like houses, vehicles or halls. Choose a location only when you want to narrow the results."}
        </p>
        <div className="mt-6 flex flex-wrap gap-3">
          <a href="#individual-marketplace" className="btn btn-success">
            {sw ? "Angalia matangazo" : "Browse listings"}
          </a>
          <Link
            href="/events/plan"
            className="btn btn-outline !border-white/30 !bg-white/10 !text-white"
          >
            {sw ? "Panga Tukio" : "Plan an event"}
          </Link>
        </div>
      </section>

      <EventsPublicCatalog />

      <section className="navy-panel grid gap-5 p-6 sm:p-8 lg:grid-cols-[1fr_auto] lg:items-center">
        <div>
          <p className="eyebrow !text-brand-amber">
            {sw ? "Huduma nyingi" : "Multiple services"}
          </p>
          <h2 className="mt-2 font-heading text-2xl font-semibold">
            {sw
              ? "Unahitaji vifaa na wataalamu kadhaa?"
              : "Need several items and professionals?"}
          </h2>
          <p className="mt-2 max-w-2xl text-sm text-white/70">
            {sw
              ? "Fungua Panga Tukio, chagua matangazo halisi kutoka portal hii, rekebisha idadi na uombe quotation moja."
              : "Open Plan an Event, choose real listings from this marketplace, adjust quantities and request one quotation."}
          </p>
        </div>
        <Link href="/events/plan" className="btn btn-success">
          {sw ? "Fungua Panga Tukio" : "Open event planner"}
        </Link>
      </section>

      <section className="grid gap-4 sm:grid-cols-3">
        {[
          sw
            ? ["1", "Chagua tangazo", "Fungua kifaa au huduma iliyochapishwa."]
            : ["1", "Choose a listing", "Open a published item or service."],
          sw
            ? ["2", "Tuma ombi", "Weka muda na taarifa zinazohitajika tu."]
            : [
                "2",
                "Send a request",
                "Provide only the required booking details.",
              ],
          sw
            ? [
                "3",
                "Thibitisha",
                "Provider anakagua upatikanaji kabla ya quotation.",
              ]
            : [
                "3",
                "Confirm",
                "The provider checks availability before quoting.",
              ],
        ].map(([number, title, body]) => (
          <article className="surface-card p-5" key={number}>
            <span className="text-sm font-extrabold text-brand-teal">
              {number}
            </span>
            <h3 className="mt-2 font-heading text-lg font-semibold">{title}</h3>
            <p className="mt-2 text-sm text-muted">{body}</p>
          </article>
        ))}
      </section>
    </div>
  );
}
