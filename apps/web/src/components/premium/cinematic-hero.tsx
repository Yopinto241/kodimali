"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useState } from "react";
import { useLanguage } from "@/components/language-provider";

type Category = { id: string; slug: string; name: string };
const slides = [
  { src: "/kodimali-premium-hero.png", slug: "house", sw: { label: "Nyumba", title: "Unatafuta nyumba ya kupanga?", body: "Chagua eneo unalotaka na uone nyumba zinazolingana na bajeti yako." }, en: { label: "Houses", title: "Looking for a house to rent?", body: "Choose your preferred location and find a home that fits your budget." } },
  { src: "/hero-apartment.png", slug: "apartment", sw: { label: "Fleti", title: "Unatafuta fleti nzuri ya kukaa?", body: "Pata fleti ya muda mfupi au mrefu katika eneo linalokufaa." }, en: { label: "Apartments", title: "Looking for a comfortable apartment?", body: "Find a short- or long-term stay in the location that suits you." } },
  { src: "/hero-vehicles.png", slug: "car", sw: { label: "Magari na pikipiki", title: "Unahitaji gari au pikipiki?", body: "Chagua usafiri unaofaa safari yako, eneo lako na bajeti yako." }, en: { label: "Cars and motorcycles", title: "Need a car or motorcycle?", body: "Choose transport that suits your journey, location, and budget." } },
  { src: "/hero-office.png", slug: "office", sw: { label: "Ofisi", title: "Unatafuta ofisi nzuri kwa biashara yako?", body: "Chagua eneo, ukubwa na bei inayokufaa, kisha uone ofisi zinazopatikana." }, en: { label: "Offices", title: "Looking for the right office for your business?", body: "Choose your preferred location, size, and budget, then explore available offices." } },
  { src: "/hero-meeting-hall.png", slug: "meeting-hall", sw: { label: "Kumbi za mikutano", title: "Unatafuta ukumbi wa mkutano?", body: "Pata ukumbi wenye nafasi na huduma zinazofaa mkutano wako." }, en: { label: "Meeting halls", title: "Looking for a meeting venue?", body: "Find a venue with the right space and services for your meeting." } },
  { src: "/hero-ceremony-hall.png", slug: "ceremony-hall", sw: { label: "Kumbi za sherehe", title: "Unapanga sherehe au tukio maalumu?", body: "Chagua ukumbi unaofaa idadi ya wageni, eneo na bajeti yako." }, en: { label: "Event halls", title: "Planning a celebration or special event?", body: "Choose a venue that fits your guests, preferred location, and budget." } },
] as const;

export function CinematicHero({ categories }: { categories: Category[] }) {
  const { language } = useLanguage();
  const [active, setActive] = useState(0);
  const [paused, setPaused] = useState(false);

  useEffect(() => {
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const saveData = "connection" in navigator && Boolean((navigator as Navigator & { connection?: { saveData?: boolean } }).connection?.saveData);
    if (reduced || saveData || paused) return;
    const timer = window.setInterval(() => {
      if (document.visibilityState === "visible") setActive((value) => (value + 1) % slides.length);
    }, 5600);
    return () => window.clearInterval(timer);
  }, [paused]);

  const slide = slides[active];
  const copy = slide[language];
  const localizedCategory = (category: Category) => language === "sw" ? ({ house: "Nyumba", apartment: "Fleti", car: "Magari", office: "Ofisi", "meeting-hall": "Kumbi za mikutano", "ceremony-hall": "Kumbi za sherehe" }[category.slug] ?? category.name) : category.name;

  return <section className="cinematic-hero" aria-roledescription="carousel" aria-label={language === "sw" ? "Aina za mali KODIMALI" : "KODIMALI asset categories"}>
    <div className="absolute inset-0 -z-20">{slides.map((item, index) => <Image key={item.src} src={item.src} alt="" fill priority={index === 0} sizes="100vw" className={`cinematic-slide object-cover ${index === active ? "is-active" : ""}`} />)}</div>
    <div className="cinematic-overlay" />
    <div className="app-shell relative z-10 flex min-h-[min(760px,82vh)] items-center py-20">
      <div className="max-w-3xl text-white">
        <p className="hero-kicker">{copy.label}</p>
        <h1 key={`${slide.slug}-${language}`} className="hero-slide-copy mt-5 font-heading text-5xl font-semibold leading-[1.02] tracking-[-0.04em] sm:text-6xl lg:text-7xl">{copy.title}</h1>
        <p className="mt-6 max-w-xl text-lg leading-8 text-white/78">{copy.body}</p>
        <form action="/listings" className="mt-8 grid gap-2 rounded-[24px] bg-white p-2 shadow-2xl sm:grid-cols-[1fr_190px_auto]">
          <label className="sr-only" htmlFor="hero-query">{language === "sw" ? "Unatafuta nini?" : "What are you looking for?"}</label><input id="hero-query" name="q" className="h-14 rounded-2xl px-4 text-brand-ink outline-none" placeholder={language === "sw" ? "Nyumba, gari, ofisi..." : "House, car, office..."} />
          <label className="sr-only" htmlFor="hero-category">{language === "sw" ? "Aina ya mali" : "Asset type"}</label><select id="hero-category" name="category" defaultValue={slide.slug} key={`select-${slide.slug}`} className="h-14 rounded-2xl bg-brand-card-soft px-4 text-brand-ink outline-none"><option value="">{language === "sw" ? "Aina zote" : "All categories"}</option>{categories.map((category) => <option value={category.slug} key={category.id}>{localizedCategory(category)}</option>)}</select>
          <button className="btn btn-success min-h-14 px-7">{language === "sw" ? "Tafuta" : "Search"}</button>
        </form>
        <div className="mt-6 flex flex-wrap items-center gap-2" role="tablist" aria-label={language === "sw" ? "Chagua aina ya mali" : "Choose an asset category"}>{slides.map((item, index) => <button key={item.slug} type="button" role="tab" aria-selected={index === active} onClick={() => { setActive(index); setPaused(true); }} className={`hero-tab ${index === active ? "is-active" : ""}`}>{item[language].label}</button>)}<button type="button" className="hero-pause" onClick={() => setPaused((value) => !value)}>{paused ? (language === "sw" ? "Endelea" : "Resume") : (language === "sw" ? "Sitisha" : "Pause")}</button></div>
        <Link className="mt-5 inline-flex text-sm font-bold text-white underline decoration-white/35 underline-offset-4" href={`/category/${slide.slug}`}>{language === "sw" ? `Angalia ${copy.label}` : `View ${copy.label}`} →</Link>
      </div>
    </div>
  </section>;
}
