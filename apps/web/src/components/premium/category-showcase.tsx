"use client";

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

  return <section className="category-showcase py-5 sm:py-7">
    <RevealOnScroll><div className="flex items-end justify-between gap-4">
      <h2 className="font-heading text-2xl font-bold tracking-tight text-brand-navy sm:text-3xl">{sw ? "Unatafuta nini?" : "What are you looking for?"}</h2>
      <Link href="/listings" className="shrink-0 text-xs font-extrabold text-brand-teal sm:text-sm">{sw ? "Angalia zote" : "View all"} <span aria-hidden="true">→</span></Link>
    </div></RevealOnScroll>
    <div className="category-rail mt-4" aria-label={sw ? "Aina za mali na huduma" : "Property and service categories"}>
      {visible.map((category, index) => {
        const media = feed.find((item) => item.category_slug === category.slug && item.cover_url);
        const isEvents = category.slug === "events";
        return <RevealOnScroll delay={Math.min(index * 45, 210)} key={category.id}>
          <Link href={isEvents ? "/events" : `/category/${category.slug}`} className={`category-mini-card group ${isEvents ? "category-mini-card-featured" : ""}`}>
            {media?.cover_url || isEvents ? <DirectMediaImage src={media?.cover_url ?? "/hero-events-edited.jpg"} alt={label(category)} sizes="(min-width: 640px) 210px, 44vw" className="category-mini-image" /> : <div className="category-fallback absolute inset-0" />}
            <div className="category-mini-shade" />
            {isEvents ? <span className="category-mini-badge">{sw ? "PANGA TUKIO" : "PLAN AN EVENT"}</span> : null}
            <div className="category-mini-copy"><h3>{label(category)}</h3>{isEvents ? <p>{sw ? "Vifaa na wataalamu" : "Equipment and professionals"}</p> : null}</div>
            <span className="category-mini-arrow" aria-hidden="true">↗</span>
          </Link>
        </RevealOnScroll>;
      })}
    </div>
  </section>;
}
