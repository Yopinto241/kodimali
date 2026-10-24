"use client";
import Link from "next/link";
import { RevealOnScroll } from "@/components/motion/reveal-on-scroll";
import { useLanguage } from "@/components/language-provider";

export function ReferralStorySection() {
  const { language } = useLanguage(); const sw = language === "sw";
  const steps = sw ? [["Tuma taarifa","Mali inayopatikana"],["Tunathibitisha","Taarifa na ruhusa"],["Tunaidhinisha","Tayari kutangazwa"],["Inapangishwa","Wakala anakamilisha"],["Zawadi","Ikiwa imestahili"]] : [["Send information","An available property"],["We verify","Details and permission"],["We approve","Ready to publish"],["It is rented","The agent completes the rental"],["Reward","When eligible"]];
  return <section className="premium-section"><div className="referral-story"><div className="referral-glow" aria-hidden />
    <RevealOnScroll className="relative z-10"><p className="premium-kicker text-brand-gold">{sw ? "Toa taarifa" : "Share a property lead"}</p><div className="mt-3 grid gap-6 lg:grid-cols-[1fr_340px] lg:items-end"><div><h2 className="max-w-2xl font-heading text-4xl font-semibold tracking-tight text-white sm:text-5xl">{sw ? "Unaijua mali inayotafuta mpangaji?" : "Know a property that needs a tenant?"}</h2><p className="mt-4 max-w-xl text-white/68">{sw ? "Tutumie taarifa. Tutazihakiki kwanza, na zawadi hutolewa masharti yakitimia." : "Send us the details. We verify them first, and a reward is paid only when the eligibility conditions are met."}</p></div><div className="referral-orbit" aria-hidden><span /><span /><span /></div></div></RevealOnScroll>
    <div className="referral-journey relative z-10 mt-12">{steps.map(([title,note],index)=><div className="referral-step" key={title}><div className="referral-step-number">{index+1}</div><div><p className="font-semibold text-white">{title}</p><p className="mt-1 text-xs text-white/48">{note}</p></div></div>)}</div>
    <div className="relative z-10 mt-10 flex flex-wrap gap-3"><Link href="/toa-taarifa" className="btn btn-gold">{sw ? "Toa taarifa" : "Send information"}</Link><Link href="/toa-taarifa#taarifa-zangu" className="btn border border-white/20 bg-white/8 text-white">{sw ? "Taarifa zangu" : "My submissions"}</Link></div>
  </div></section>;
}
