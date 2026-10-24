"use client";
import Link from "next/link";
import { useLanguage } from "@/components/language-provider";
import { SectionHeading } from "@/components/section-heading";
export function VerificationCard(){const{language}=useLanguage();const sw=language==="sw";return <section className="premium-section grid gap-6 rounded-[32px] border border-brand-border bg-white p-7 md:grid-cols-[1fr_auto] md:items-center sm:p-10"><div><SectionHeading eyebrow={sw?"Uhakiki":"Verification"} title={sw?"Tunahakikisha taarifa kabla ya kutangaza":"We verify information before publication"} description={sw?"Tunahakikisha mali ipo, taarifa zake ni sahihi na mwenye mali ameruhusu itangazwe.":"We confirm that the property exists, its details are accurate, and the owner has permitted its publication."}/></div><Link href="/safety" className="btn btn-outline">{sw?"Jinsi uhakiki unavyofanyika":"How verification works"}</Link></section>}
