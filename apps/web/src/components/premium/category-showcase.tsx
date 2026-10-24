"use client";
import Link from "next/link";
import { DirectMediaImage } from "@/components/direct-media-image";
import { RevealOnScroll } from "@/components/motion/reveal-on-scroll";
import { useLanguage } from "@/components/language-provider";
type Category={id:string;slug:string;name:string}; type FeedItem={category_slug:string;cover_url?:string|null;title?:string};
export function CategoryShowcase({categories,feed}:{categories:Category[];feed:FeedItem[]}) {
 const {language}=useLanguage(); const sw=language==="sw";
 const label=(category:Category)=>sw?({house:"Nyumba",apartment:"Fleti",car:"Magari",office:"Ofisi","meeting-hall":"Kumbi za mikutano","ceremony-hall":"Kumbi za sherehe"}[category.slug]??category.name):category.name;
 return <section className="premium-section"><RevealOnScroll><p className="premium-kicker">{sw?"Aina za mali":"Asset categories"}</p><div className="mt-3 flex items-end justify-between gap-4"><h2 className="premium-title">{sw?"Unatafuta mali gani?":"What are you looking for?"}</h2><Link href="/listings" className="text-sm font-bold text-brand-teal">{sw?"Angalia zote":"View all"} →</Link></div></RevealOnScroll><div className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">{categories.slice(0,8).map((category,index)=>{const media=feed.find(item=>item.category_slug===category.slug&&item.cover_url);return <RevealOnScroll delay={Math.min(index*55,220)} key={category.id}><Link href={category.slug==="events"?"/events":`/category/${category.slug}`} className="category-card group"><div className="relative aspect-[4/3] overflow-hidden bg-brand-card-soft">{media?.cover_url?<DirectMediaImage src={media.cover_url} alt="" sizes="(min-width:1024px) 25vw, 50vw" className="h-full w-full object-cover transition duration-500 group-hover:scale-105"/>:<div className="category-fallback h-full"/>}<div className="absolute inset-0 bg-gradient-to-t from-[#102438]/80 via-transparent to-transparent"/><h3 className="absolute bottom-4 left-4 font-heading text-xl font-semibold text-white">{label(category)}</h3></div></Link></RevealOnScroll>})}</div></section>;
}
