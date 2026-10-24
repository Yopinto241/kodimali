"use client";
import type { PointerEvent } from "react";
import Link from "next/link";
import { DirectMediaImage } from "@/components/direct-media-image";
import { RevealOnScroll } from "@/components/motion/reveal-on-scroll";
import { useLanguage } from "@/components/language-provider";

type Category = { id: string; slug: string; name: string };
type FeedItem = { category_slug: string; cover_url?: string | null; title?: string };

export function CategoryShowcase({ categories, feed }: { categories: Category[]; feed: FeedItem[] }) {
  const { language } = useLanguage();
  const sw = language === "sw";
  const eventCategory = categories.find((item) => item.slug === "events");
  const visible = [...(eventCategory ? [eventCategory] : [{ id: "events", slug: "events", name: "Ceremonies & Events" }]), ...categories.filter((item) => item.slug !== "events")].slice(0, 8);
  const label = (category: Category) => sw ? ({ events: "Sherehe na Matukio", house: "Nyumba", apartment: "Fleti", car: "Magari", motorcycle: "Pikipiki", office: "Ofisi", "meeting-hall": "Kumbi za mikutano", "ceremony-hall": "Kumbi za sherehe", equipment: "Vifaa", farms: "Mashamba", "other-asset": "Mali nyingine" }[category.slug] ?? category.name) : category.name;
  const moveCardLight = (event: PointerEvent<HTMLAnchorElement>) => {
    const bounds = event.currentTarget.getBoundingClientRect();
    event.currentTarget.style.setProperty("--card-x", `${event.clientX - bounds.left}px`);
    event.currentTarget.style.setProperty("--card-y", `${event.clientY - bounds.top}px`);
  };
  return <section className="pb-10 pt-2 sm:pb-14 sm:pt-3">
    <RevealOnScroll><div className="flex items-end justify-between gap-4"><h2 className="premium-title">{sw ? "Unatafuta nini?" : "What are you looking for?"}</h2><Link href="/listings" className="text-sm font-bold text-brand-teal">{sw ? "Angalia rentals zote" : "View all rentals"} →</Link></div></RevealOnScroll>
    <div className="category-compact-grid mt-6">{visible.map((category, index) => {
      const media = feed.find((item) => item.category_slug === category.slug && item.cover_url);
      const isEvents = category.slug === "events";
      return <RevealOnScroll delay={Math.min(index * 55, 220)} key={category.id}><Link onPointerMove={moveCardLight} href={isEvents ? "/events" : `/category/${category.slug}`} className={`category-card group ${isEvents ? "ring-2 ring-brand-amber/70" : ""}`}><div className="relative h-full overflow-hidden bg-brand-card-soft">{media?.cover_url ? <DirectMediaImage src={media.cover_url} alt="" sizes="(min-width:1024px) 140px, 45vw" className="h-full w-full object-cover transition duration-500 group-hover:scale-105" /> : isEvents ? <DirectMediaImage src="/hero-events-edited.jpg" alt="" sizes="(min-width:1024px) 140px, 45vw" className="h-full w-full object-cover transition duration-500 group-hover:scale-105" /> : <div className="category-fallback h-full" />}<div className="absolute inset-0 bg-gradient-to-t from-[#102438]/90 via-[#102438]/10 to-transparent" />{isEvents ? <span className="absolute left-2 top-2 z-10 rounded-full bg-brand-amber px-2 py-0.5 text-[8px] font-extrabold text-brand-navy">{sw ? "PANGA EVENT" : "PLAN AN EVENT"}</span> : null}<div className="absolute bottom-2 left-2 right-2 z-10"><h3 className="font-heading text-sm font-semibold leading-tight text-white">{label(category)}</h3>{isEvents ? <p className="mt-0.5 truncate text-[9px] text-white/80">{sw ? "Vifaa na wataalamu" : "Equipment and professionals"}</p> : null}</div></div></Link></RevealOnScroll>;
    })}</div>
  </section>;
}
