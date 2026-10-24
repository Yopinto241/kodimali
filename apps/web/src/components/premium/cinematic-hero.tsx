"use client";
import Image from "next/image";
import Link from "next/link";
import { useEffect, useState } from "react";
import { useLanguage } from "@/components/language-provider";

type Category = { id: string; slug: string; name: string };
type Copy = { label: string; title: string; body: string };
type Slide = { src: string; slug: string; position: string; sw: Copy; en: Copy };
const slide = (src: string, slug: string, sw: Copy, en: Copy, position = "center"): Slide => ({ src, slug, sw, en, position });
const slides = [
  slide("/hero-house-real.jpg", "house", { label: "Nyumba", title: "Pata nyumba inayokufaa.", body: "Chagua eneo na bajeti, kisha anza kuona mali sasa." }, { label: "Houses", title: "Find a home that fits.", body: "Choose a location and budget, then start browsing now." }),
  slide("/hero-house-real.jpg", "apartment", { label: "Fleti", title: "Pata fleti nzuri.", body: "Chagua eneo, muda wa kukaa na bajeti yako." }, { label: "Apartments", title: "Find a comfortable apartment.", body: "Choose your location, stay length and budget." }, "center 60%"),
  slide("/hero-car-edited.jpg", "car", { label: "Magari", title: "Unahitaji gari?", body: "Tafuta usafiri unaofaa safari na bajeti yako." }, { label: "Cars", title: "Need a car?", body: "Find transport that suits your journey and budget." }),
  slide("/hero-motorcycle-edited.jpg", "motorcycle", { label: "Pikipiki", title: "Tafuta pikipiki.", body: "Chagua pikipiki inayofaa matumizi yako." }, { label: "Motorcycles", title: "Find a motorcycle.", body: "Choose a motorcycle that suits your needs." }),
  slide("/hero-office-edited.jpg", "office", { label: "Ofisi", title: "Tafuta nafasi ya biashara.", body: "Chagua eneo na ukubwa wa ofisi unaohitaji." }, { label: "Offices", title: "Find your business space.", body: "Choose the location and office size you need." }),
  slide("/hero-hall-edited.jpg", "meeting-hall", { label: "Ukumbi wa mikutano", title: "Pata ukumbi wa mkutano.", body: "Linganisha nafasi kwa eneo, uwezo na bei." }, { label: "Meeting halls", title: "Find a meeting venue.", body: "Compare spaces by location, capacity and price." }),
  slide("/hero-hall-edited.jpg", "ceremony-hall", { label: "Ukumbi wa sherehe", title: "Pata ukumbi wa sherehe.", body: "Chagua nafasi inayowatosha wageni wako." }, { label: "Ceremony halls", title: "Find a ceremony venue.", body: "Choose a space that fits your guests." }, "center 55%"),
  slide("/hero-equipment-edited.jpg", "equipment", { label: "Vifaa", title: "Kodisha vifaa unavyohitaji.", body: "Pata vifaa vya kazi na matukio kwa urahisi." }, { label: "Equipment", title: "Rent the equipment you need.", body: "Find equipment for work and events." }),
  slide("/hero-farm-edited.jpg", "farms", { label: "Mashamba", title: "Tafuta shamba linalokufaa.", body: "Linganisha eneo, ukubwa na matumizi ya ardhi." }, { label: "Farms", title: "Find the right farm.", body: "Compare location, size and land use." }),
  slide("/hero-other-edited.jpg", "other-asset", { label: "Mali nyingine", title: "Tafuta mali nyingine.", body: "Gundua chaguo zaidi za kukodisha." }, { label: "Other assets", title: "Find other rentable assets.", body: "Discover more rental options." }),
  slide("/hero-events-edited.jpg", "events", { label: "Matukio", title: "Panga tukio kwa urahisi.", body: "Pata ukumbi, vifaa na wataalamu mahali pamoja." }, { label: "Events", title: "Plan your event with ease.", body: "Find venues, equipment and professionals together." }),
];

export function CinematicHero({ categories }: { categories: Category[] }) {
  const { language } = useLanguage();
  const [active, setActive] = useState(0);
  const [paused, setPaused] = useState(false);
  useEffect(() => {
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const saveData = "connection" in navigator && Boolean((navigator as Navigator & { connection?: { saveData?: boolean } }).connection?.saveData);
    if (reduced || saveData || paused) return;
    const timer = window.setInterval(() => { if (document.visibilityState === "visible") setActive((value) => (value + 1) % slides.length); }, 4800);
    return () => window.clearInterval(timer);
  }, [paused]);
  const activeSlide = slides[active];
  const copy = activeSlide[language];
  const localizedCategory = (category: Category) => language === "sw" ? ({ house: "Nyumba", apartment: "Fleti", car: "Magari", motorcycle: "Pikipiki", office: "Ofisi", "meeting-hall": "Kumbi za mikutano", "ceremony-hall": "Kumbi za sherehe", equipment: "Vifaa", farms: "Mashamba", "other-asset": "Mali nyingine", events: "Matukio" }[category.slug] ?? category.name) : category.name;
  const href = activeSlide.slug === "events" ? "/events" : `/category/${activeSlide.slug}`;
  return <section className="cinematic-hero" aria-roledescription="carousel">
    <div className="absolute inset-0 -z-20">{slides.map((item, index) => <Image key={item.slug} src={item.src} alt="" fill priority={index === 0} sizes="100vw" style={{ objectPosition: item.position }} className={`cinematic-slide object-cover ${index === active ? "is-active" : ""}`} />)}</div>
    <div className="cinematic-overlay" />
    <div className="app-shell relative z-10 flex min-h-[300px] items-center py-5"><div className="w-full max-w-4xl text-white">
      <p className="hero-kicker">{copy.label}</p>
      <h1 key={`${activeSlide.slug}-${language}`} className="hero-slide-copy mt-1 font-heading text-3xl font-semibold leading-tight tracking-[-0.035em] sm:text-4xl">{copy.title}</h1>
      <p className="mt-1 max-w-xl text-sm text-white/85 sm:text-base">{copy.body}</p>
      <form action="/listings" className="hero-search-form mt-3 grid gap-1.5 rounded-2xl bg-white p-1.5 shadow-2xl sm:grid-cols-[1fr_180px_auto]">
        <input name="q" aria-label={language === "sw" ? "Unatafuta nini?" : "What are you looking for?"} className="hero-search-input h-11 rounded-xl px-4 text-brand-ink outline-none" placeholder={language === "sw" ? "Nyumba, gari, ofisi..." : "House, car, office..."} />
        <select name="category" aria-label={language === "sw" ? "Aina ya mali" : "Asset type"} defaultValue={activeSlide.slug} key={activeSlide.slug} className="hero-search-category h-11 rounded-xl bg-brand-card-soft px-4 text-brand-ink outline-none"><option value="">{language === "sw" ? "Aina zote" : "All categories"}</option>{categories.map((category) => <option value={category.slug} key={category.id}>{localizedCategory(category)}</option>)}</select>
        <button className="hero-search-button btn btn-success min-h-11 px-6">{language === "sw" ? "Tafuta" : "Search"}</button>
      </form>
      <div className="hero-tabs mt-2 flex items-center gap-1.5 overflow-x-auto pb-1" role="tablist">{slides.map((item, index) => <button key={item.slug} type="button" role="tab" aria-selected={index === active} onClick={() => { setActive(index); setPaused(true); }} className={`hero-tab ${index === active ? "is-active" : ""}`}>{item[language].label}</button>)}<button type="button" className="hero-pause" onClick={() => setPaused((value) => !value)}>{paused ? (language === "sw" ? "Endelea" : "Resume") : (language === "sw" ? "Sitisha" : "Pause")}</button></div>
      <Link className="mt-1 inline-flex text-xs font-bold text-white underline decoration-white/35 underline-offset-4" href={href}>{language === "sw" ? `Angalia ${copy.label}` : `View ${copy.label}`} →</Link>
    </div></div>
  </section>;
}
