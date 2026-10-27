"use client";

import Link from "next/link";
import { RevealOnScroll } from "@/components/motion/reveal-on-scroll";
import { useLanguage } from "@/components/language-provider";

export function ReferralStorySection() {
  const { language } = useLanguage();
  const sw = language === "sw";
  const steps = sw
    ? [["Tuma", "Maelezo ya mali"], ["Tunahakiki", "Mali na ruhusa"], ["Fuatilia", "Hatua na zawadi"]]
    : [["Send", "Property details"], ["We verify", "Property and permission"], ["Track", "Progress and reward"]];

  return (
    <section className="py-8 sm:py-12">
      <div className="referral-story referral-story-compact">
        <RevealOnScroll className="relative z-10">
          <p className="premium-kicker text-brand-gold">{sw ? "Toa taarifa" : "Share a lead"}</p>
          <div className="mt-3 grid gap-5 lg:grid-cols-[1fr_auto] lg:items-end">
            <div>
              <h2 className="max-w-2xl font-heading text-3xl font-semibold tracking-tight text-white sm:text-4xl">{sw ? "Unaijua mali inayopatikana?" : "Know an available property?"}</h2>
              <p className="mt-3 max-w-xl text-sm text-white/70">{sw ? "Tutumie taarifa. Tutathibitisha mali na kukuarifu hatua inayofuata." : "Send the details. We will verify the property and update you."}</p>
            </div>
            <div className="flex flex-wrap gap-2"><Link href="/toa-taarifa" className="btn btn-gold">{sw ? "Toa taarifa" : "Send details"}</Link><Link href="/toa-taarifa#taarifa-zangu" className="btn border border-white/20 bg-white/8 text-white">{sw ? "Taarifa zangu" : "My submissions"}</Link></div>
          </div>
        </RevealOnScroll>
        <div className="relative z-10 mt-7 grid gap-2 sm:grid-cols-3">
          {steps.map(([title, note], index) => <div className="referral-step" key={title}><div className="referral-step-number">{index + 1}</div><div><p className="font-semibold text-white">{title}</p><p className="text-xs text-white/50">{note}</p></div></div>)}
        </div>
      </div>
    </section>
  );
}
