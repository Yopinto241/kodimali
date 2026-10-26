"use client";
import type { PointerEvent } from "react";
import Link from "next/link";
import { DirectMediaImage } from "@/components/direct-media-image";
import { RevealOnScroll } from "@/components/motion/reveal-on-scroll";
import { useLanguage } from "@/components/language-provider";

type Category = { id: string; slug: string; name: string };
type FeedItem = { category_slug: string; cover_url?: string | null; title?: string };

const categoryFallbackImage: Record<string, string> = {
  events: "/hero-events-edited.jpg",
  house: "/hero-house-real.jpg",
  apartment: "/hero-house-real.jpg",
  car: "/hero-car-edited.jpg",
  motorcycle: "/hero-motorcycle-edited-v2.jpg",
  office: "/hero-office-edited.jpg",
  "meeting-hall": "/hero-hall-edited.jpg",
  "ceremony-hall": "/hero-hall-edited.jpg",
  equipment: "/hero-equipment-edited.jpg",
  farms: "/hero-farm-edited.jpg",
  "other-asset": "/hero-other-edited.jpg",
};

export function CategoryShowcase({ categories, feed }: { categories: Category[]; feed: FeedItem[] }) {
  const { language } = useLanguage();
  const sw = language === "sw";
  const preferred = ["house", "car", "office", "meeting-hall", "ceremony-hall", "equipment"];
  const visible = preferred
    .map((slug) => categories.find((item) => item.slug === slug))
    .filter((item): item is Category => Boolean(item));
  const label = (category: Category) => sw ? ({ events: "Sherehe na Matukio", house: "Nyumba", apartment: "Apartment", car: "Magari", motorcycle: "Pikipiki", office: "Ofisi", "meeting-hall": "Kumbi za mikutano", "ceremony-hall": "Kumbi za sherehe", equipment: "Vifaa", farms: "Mashamba", "other-asset": "Mali nyingine" }[category.slug] ?? category.name) : category.name;
  const moveCardLight = (event: PointerEvent<HTMLAnchorElement>) => {
    const bounds = event.currentTarget.getBoundingClientRect();
    event.currentTarget.style.setProperty("--card-x", `${event.clientX - bounds.left}px`);
    event.currentTarget.style.setProperty("--card-y", `${event.clientY - bounds.top}px`);
  };
  return <section className="home-category-section pb-5 pt-5 sm:pb-7 sm:pt-7">
    <RevealOnScroll><div className="flex items-end justify-between gap-4"><h2 className="home-category-title">{sw ? "Unatafuta nini?" : "What are you looking for?"}</h2><Link href="/listings" className="home-category-all">{sw ? "Tazama zote" : "View all"} →</Link></div></RevealOnScroll>
    <div className="category-compact-grid mt-6">{visible.map((category, index) => {
      const media = feed.find((item) => item.category_slug === category.slug && item.cover_url);
      const isEvents = category.slug === "events";
      const image = media?.cover_url ?? categoryFallbackImage[category.slug] ?? "/hero-other-edited.jpg";
      return <RevealOnScroll delay={Math.min(index * 55, 220)} key={category.id}><Link onPointerMove={moveCardLight} href={isEvents ? "/events" : `/category/${category.slug}`} className="category-card group"><div className="relative h-full overflow-hidden bg-brand-card-soft"><DirectMediaImage src={image} alt={media?.title ?? label(category)} sizes="(min-width:1024px) 190px, 33vw" className="h-full w-full object-cover transition duration-500 group-hover:scale-105" /><div className="absolute inset-0 bg-gradient-to-t from-[#071e2a]/95 via-[#102438]/10 to-transparent" /><div className="absolute bottom-2.5 left-2.5 right-2.5 z-10"><h3 className="font-heading text-sm font-bold leading-tight text-white">{label(category)}</h3><p className="mt-0.5 truncate text-[9px] text-white/75">{sw ? "Angalia chaguo" : "Browse options"}</p></div></div></Link></RevealOnScroll>;
    })}</div>
  </section>;
}
