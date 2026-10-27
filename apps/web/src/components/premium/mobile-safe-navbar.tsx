"use client";
import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { AuthActions } from "@/components/auth-actions";
import { LanguageSwitch } from "@/components/language-switch";
import { useLanguage } from "@/components/language-provider";
type Category={id:string;slug:string;name:string};
const links=[{href:"/",label:"nav.home"},{href:"/listings",label:"nav.listings"},{href:"/events",label:"nav.events"},{href:"/toa-taarifa",label:"nav.referral"},{href:"/compare",label:"nav.compare"}] as const;
const active=(path:string,href:string)=>href==="/"?path==="/":path.startsWith(href);
export function MobileSafeNavbar({categories}:{categories:Category[]}){
 const path=usePathname();const{t}=useLanguage();const[menu,setMenu]=useState(false);const[cats,setCats]=useState(false);const[scrolled,setScrolled]=useState(false);const ref=useRef<HTMLDivElement>(null);
 useEffect(()=>{const fn=()=>setScrolled(scrollY>18);fn();addEventListener("scroll",fn,{passive:true});return()=>removeEventListener("scroll",fn)},[]);
 useEffect(()=>{const frame=requestAnimationFrame(()=>{setMenu(false);setCats(false)});return()=>cancelAnimationFrame(frame)},[path]);
 useEffect(()=>{if(!menu)return;const b=document.body.style.overflow,h=document.documentElement.style.overflow;document.body.style.overflow="hidden";document.documentElement.style.overflow="hidden";return()=>{document.body.style.overflow=b;document.documentElement.style.overflow=h}},[menu]);
 useEffect(()=>{const outside=(e:PointerEvent)=>{if(ref.current&&!ref.current.contains(e.target as Node))setCats(false)};const key=(e:KeyboardEvent)=>{if(e.key==="Escape"){setCats(false);setMenu(false)}};document.addEventListener("pointerdown",outside);document.addEventListener("keydown",key);return()=>{document.removeEventListener("pointerdown",outside);document.removeEventListener("keydown",key)}},[]);
 const href=(c:Category)=>c.slug==="events"?"/events":`/category/${c.slug}`;
 return <header className={`premium-nav ${scrolled?"is-scrolled":""}`}><div className="app-shell flex h-16 items-center justify-between gap-3"><Link href="/" className="flex min-w-0 items-center gap-2.5"><span className="flex h-9 w-9 items-center justify-center overflow-hidden rounded-xl bg-white"><Image src="/icon.png" alt="" width={32} height={32} priority/></span><span className="truncate font-heading text-base font-extrabold tracking-[.15em] text-brand-navy">KODIMALI</span></Link>
 <nav className="hidden items-center gap-1 lg:flex">{links.map(x=><Link className={`nav-link ${active(path,x.href)?"is-active":""}`} href={x.href} key={x.href}>{t(x.label)}</Link>)}<div className="relative" ref={ref}><button className={`nav-link ${path.startsWith("/category/")?"is-active":""}`} onClick={()=>{setMenu(false);setCats(v=>!v)}}>{t("nav.categories")} {cats?"⌃":"⌄"}</button>{cats?<div className="nav-category-menu">{categories.map(c=><Link className="nav-category-link" href={href(c)} key={c.id}>{c.name}</Link>)}</div>:null}</div></nav>
 <div className="hidden items-center gap-2 lg:flex"><LanguageSwitch/><AuthActions/></div><div className="flex items-center gap-2 lg:hidden"><LanguageSwitch/><button className="nav-menu-toggle" onClick={()=>{setCats(false);setMenu(v=>!v)}} aria-expanded={menu} aria-label={menu?"Funga menyu":"Fungua menyu"}>{menu?"×":"☰"}</button></div></div>
 {menu?<div className="mobile-nav-layer lg:hidden" onPointerDown={e=>{if(e.target===e.currentTarget)setMenu(false)}}><div className="mobile-nav-panel"><nav className="grid grid-cols-2 gap-2">{links.map(x=><Link className={`mobile-nav-link ${active(path,x.href)?"is-active":""}`} href={x.href} key={x.href} onClick={()=>setMenu(false)}>{t(x.label)}</Link>)}</nav><div className="mobile-nav-divider"/><p className="mobile-nav-label">{t("nav.categories")}</p><div className="mobile-category-grid">{categories.slice(0,8).map(c=><Link href={href(c)} key={c.id} onClick={()=>setMenu(false)}>{c.name}</Link>)}</div></div></div>:null}</header>
}
