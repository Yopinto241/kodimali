"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { AuthActions } from "@/components/auth-actions";
import { LanguageSwitch } from "@/components/language-switch";
import { useLanguage } from "@/components/language-provider";

type Category = { id: string; slug: string; name: string };
const links = [
  { href: "/", label: "nav.home" },
  { href: "/listings", label: "nav.listings" },
  { href: "/events", label: "nav.events" },
  { href: "/toa-taarifa", label: "nav.referral" },
  { href: "/compare", label: "nav.compare" },
] as const;

function isActive(pathname: string, href: string) {
  return href === "/" ? pathname === "/" : pathname.startsWith(href);
}

export function PremiumNavbar({ categories }: { categories: Category[] }) {
  const pathname = usePathname();
  const { t } = useLanguage();
  const [scrolled, setScrolled] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);

  useEffect(() => {
    const update = () => setScrolled(window.scrollY > 18);
    update();
    window.addEventListener("scroll", update, { passive: true });
    return () => window.removeEventListener("scroll", update);
  }, []);

  return (
    <header className={`premium-nav ${scrolled ? "is-scrolled" : ""}`}>
      <div className="app-shell flex h-16 items-center justify-between gap-4">
        <Link href="/" className="flex items-center gap-3" aria-label="KODIMALI mwanzo">
          <span className="flex h-9 w-9 items-center justify-center overflow-hidden rounded-xl bg-white shadow-sm"><Image src="/icon.png" alt="" width={32} height={32} priority /></span>
          <span className="font-heading text-lg font-extrabold tracking-[0.16em] text-brand-navy">KODIMALI</span>
        </Link>

        <nav className="hidden items-center gap-1 lg:flex" aria-label="Urambazaji mkuu">
          {links.map((item) => {
            const active = isActive(pathname, item.href);
            return <Link className={`nav-link ${active ? "is-active" : ""}`} href={item.href} key={item.href} aria-current={active ? "page" : undefined}>{t(item.label)}</Link>;
          })}
          <div className="group relative">
            <button className={`nav-link ${pathname.startsWith("/category/") ? "is-active" : ""}`} type="button">{t("nav.categories")}</button>
            <div className="invisible absolute left-1/2 top-full z-20 mt-2 w-56 -translate-x-1/2 rounded-2xl border border-brand-border bg-white p-2 opacity-0 shadow-xl transition group-hover:visible group-hover:opacity-100 group-focus-within:visible group-focus-within:opacity-100">
              {categories.map((category) => <Link className="block rounded-xl px-3 py-2 text-sm font-semibold hover:bg-brand-card-soft" href={category.slug === "events" ? "/events" : `/category/${category.slug}`} key={category.id}>{category.name}</Link>)}
            </div>
          </div>
        </nav>

        <div className="hidden items-center gap-2 lg:flex">
          <form action="/listings" className="nav-search"><label className="sr-only" htmlFor="nav-search">{t("nav.search")}</label><input id="nav-search" name="q" placeholder={`${t("nav.search")}...`} /><button aria-label={t("nav.search")}>⌕</button></form>
          <LanguageSwitch />
          <AuthActions />
        </div>
        <button className="flex h-11 w-11 items-center justify-center rounded-full border border-brand-border bg-white text-xl lg:hidden" onClick={() => setMenuOpen((value) => !value)} aria-expanded={menuOpen} aria-controls="mobile-menu" aria-label="Fungua menyu">{menuOpen ? "×" : "☰"}</button>
      </div>

      {menuOpen ? (
        <div id="mobile-menu" className="border-t border-brand-border bg-white p-4 shadow-xl lg:hidden">
          <nav className="app-shell grid gap-2" aria-label="Urambazaji wa simu">
            {links.map((item) => {
              const active = isActive(pathname, item.href);
              return <Link className={`rounded-2xl px-4 py-3 font-semibold transition ${active ? "bg-brand-navy text-white shadow-sm" : "text-brand-navy hover:bg-brand-card-soft"}`} href={item.href} key={item.href} onClick={() => setMenuOpen(false)} aria-current={active ? "page" : undefined}>{item.href === "/" ? <span className="mr-2" aria-hidden="true">⌂</span> : null}{t(item.label)}</Link>;
            })}
            <Link className={`rounded-2xl px-4 py-3 font-semibold transition ${pathname.startsWith("/account") ? "bg-brand-navy text-white shadow-sm" : "text-brand-navy hover:bg-brand-card-soft"}`} href="/account" onClick={() => setMenuOpen(false)}>{t("nav.account")}</Link>
            <LanguageSwitch />
            <form action="/listings" className="mt-2 flex gap-2"><input className="field-input" name="q" placeholder={t("nav.search")} /><button className="btn btn-primary">{t("nav.search")}</button></form>
            <div className="mt-2 flex gap-2"><AuthActions mobile /></div>
          </nav>
        </div>
      ) : null}
    </header>
  );
}
