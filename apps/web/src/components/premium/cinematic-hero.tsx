"use client";
import Image from "next/image";
import Link from "next/link";
import { useEffect, useState } from "react";
import { useLanguage } from "@/components/language-provider";

type Category = { id: string; slug: string; name: string };
const slides = [
  { src: "/hero-house-real.jpg", slug: "house", position: "center", sw: { label: "Nyumba", title: "Pata nyumba inayokufaa.", body: "Chagua eneo na bajeti, kisha anza kuona mali sasa." }, en: { label: "Houses", title: "Find a home that fits.", body: "Choose a location and budget, then start browsing now." } },
  { src: "/gari.jpg", slug: "car", position: "center 58%", sw: { label: "Magari", title: "Unahitaji usafiri?", body: "Tafuta gari linalofaa safari na bajeti yako." }, en: { label: "Vehicles", title: "Need transport?", body: "Find a vehicle that suits your journey and budget." } },
  { src: "/ofisi.jpg", slug: "office", position: "center", sw: { label: "Ofisi", title: "Tafuta nafasi ya biashara.", body: "Chagua eneo na ukubwa wa ofisi unaohitaji." }, en: { label: "Offices", title: "Find your business space.", body: "Choose the location and office size you need." } },
  { src: "/kumbi2.jpg", slug: "meeting-hall", position: "center 46%", sw: { label: "Kumbi", title: "Pata ukumbi unaofaa.", body: "Linganisha nafasi kwa eneo, idadi ya watu na bei." }, en: { label: "Venues", title: "Find the right venue.", body: "Compare spaces by location, capacity and price." } },
  { src: "/mapambo.jpg", slug: "events", position: "center", sw: { label: "Matukio", title: "Panga tukio lako kwa urahisi.", body: "Pata ukumbi, vifaa na wataalamu mahali pamoja." }, en: { label: "Events", title: "Plan your event with ease.", body: "Find venues, equipment and professionals in one place." } },
] as const;

export function CinematicHero({ categories }: { categories: Category[] }) {
  const { language } = useLanguage();
  const [active, setActive] = useState(0);
  const [paused, setPaused] = useState(false);
  useEffect(() => {
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const saveData = "connection" in navigator && Boolean((navigator as Navigator & { connection?: { saveData?: boolean } }).connection?.saveData);
    if (reduced || saveData || paused) return;
    const timer = window.setInterval(() => { if (document.visibilityState === "visible") setActive((value) => (value + 1) % slides.length); }, 5600);
    return () => window.clearInterval(timer);
  }, [paused]);
  const slide = slides[active];
  const copy = slide[language];
  const localizedCategory = (category: Category) => language === "sw" ? ({ house: "Nyumba", apartment: "Fleti", car: "Magari", office: "Ofisi", "meeting-hall": "Kumbi za mikutano", "ceremony-hall": "Kumbi za sherehe", events: "Matukio" }[category.slug] ?? category.name) : category.name;
  const slideHref = slide.slug === "events" ? "/events" : `/category/${slide.slug}`;
  return <section className="cinematic-hero" aria-roledescription="carousel" aria-label={language === "sw" ? "Aina za mali KODIMALI" : "KODIMALI asset categories"}>
    <div className="absolute inset-0 -z-20">{slides.map((item, index) => <Image key={item.src} src={item.src} alt="" fill priority={index === 0} sizes="100vw" style={{ objectPosition: item.position }} className={`cinematic-slide object-cover ${index === active ? "is-active" : ""}`} />)}</div>
    <div className="cinematic-overlay" />
    <div className="app-shell relative z-10 flex min-h-[min(520px,66vh)] items-center py-10 sm:py-12"><div className="max-w-3xl text-white">
      <p className="hero-kicker">{copy.label}</p>
      <h1 key={`${slide.slug}-${language}`} className="hero-slide-copy mt-3 font-heading text-4xl font-semibold leading-[1.04] tracking-[-0.04em] sm:text-5xl lg:text-6xl">{copy.title}</h1>
      <p className="mt-3 max-w-xl text-base leading-7 text-white/82 sm:text-lg">{copy.body}</p>
      <form action="/listings" className="mt-5 grid gap-2 rounded-[20px] bg-white p-2 shadow-2xl sm:grid-cols-[1fr_180px_auto]">
        <label className="sr-only" htmlFor="hero-query">{language === "sw" ? "Unatafuta nini?" : "What are you looking for?"}</label><input id="hero-query" name="q" className="h-12 rounded-2xl px-4 text-brand-ink outline-none" placeholder={language === "sw" ? "Nyumba, gari, ofisi..." : "House, car, office..."} />
        <label className="sr-only" htmlFor="hero-category">{language === "sw" ? "Aina ya mali" : "Asset type"}</label><select id="hero-category" name="category" defaultValue={slide.slug} key={`select-${slide.slug}`} className="h-12 rounded-2xl bg-brand-card-soft px-4 text-brand-ink outline-none"><option value="">{language === "sw" ? "Aina zote" : "All categories"}</option>{categories.map((category) => <option value={category.slug} key={category.id}>{localizedCategory(category)}</option>)}</select>
        <button className="btn btn-success min-h-12 px-7">{language === "sw" ? "Tafuta" : "Search"}</button>
      </form>
      <div className="mt-4 flex flex-wrap items-center gap-2" role="tablist">{slides.map((item, index) => <button key={item.slug} type="button" role="tab" aria-selected={index === active} onClick={() => { setActive(index); setPaused(true); }} className={`hero-tab ${index === active ? "is-active" : ""}`}>{item[language].label}</button>)}<button type="button" className="hero-pause" onClick={() => setPaused((value) => !value)}>{paused ? (language === "sw" ? "Endelea" : "Resume") : (language === "sw" ? "Sitisha" : "Pause")}</button></div>
      <Link className="mt-3 inline-flex text-sm font-bold text-white underline decoration-white/35 underline-offset-4" href={slideHref}>{language === "sw" ? `Angalia ${copy.label}` : `View ${copy.label}`} →</Link>
    </div></div>
  </section>;
}
