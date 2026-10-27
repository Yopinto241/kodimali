"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";
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
  const [categoriesOpen, setCategoriesOpen] = useState(false);
  const categoryMenuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const update = () => setScrolled(window.scrollY > 18);
    update();
    window.addEventListener("scroll", update, { passive: true });
    return () => window.removeEventListener("scroll", update);
  }, []);

  useEffect(() => {
    const closeMobileAtDesktop = () => {
      if (window.innerWidth >= 1024) setMenuOpen(false);
    };
    window.addEventListener("resize", closeMobileAtDesktop, { passive: true });
    return () => window.removeEventListener("resize", closeMobileAtDesktop);
  }, []);

  useEffect(() => {
    setMenuOpen(false);
    setCategoriesOpen(false);
  }, [pathname]);

  useEffect(() => {
    if (!menuOpen) return;
    const previousBody = document.body.style.overflow;
    const previousHtml = document.documentElement.style.overflow;
    document.body.style.overflow = "hidden";
    document.documentElement.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = previousBody;
      document.documentElement.style.overflow = previousHtml;
    };
  }, [menuOpen]);

  useEffect(() => {
    const closeMenus = (event: MouseEvent) => {
      if (categoryMenuRef.current && !categoryMenuRef.current.contains(event.target as Node)) {
        setCategoriesOpen(false);
      }
    };
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setCategoriesOpen(false);
        setMenuOpen(false);
      }
    };
    document.addEventListener("pointerdown", closeMenus);
    document.addEventListener("keydown", closeOnEscape);
    return () => {
      document.removeEventListener("pointerdown", closeMenus);
      document.removeEventListener("keydown", closeOnEscape);
    };
  }, []);

  const categoryHref = (category: Category) => category.slug === "events" ? "/events" : `/category/${category.slug}`;

  return (
    <header className={`premium-nav ${scrolled ? "is-scrolled" : ""}`}>
      <div className="app-shell flex h-16 items-center justify-between gap-3">
        <Link href="/" className="flex min-w-0 items-center gap-2.5" aria-label="KODIMALI mwanzo">
          <span className="flex h-9 w-9 flex-none items-center justify-center overflow-hidden rounded-xl bg-white shadow-sm"><Image src="/icon.png" alt="" width={32} height={32} priority /></span>
          <span className="truncate font-heading text-base font-extrabold tracking-[0.15em] text-brand-navy sm:text-lg">KODIMALI</span>
        </Link>

        <nav className="hidden items-center gap-1 lg:flex" aria-label="Urambazaji mkuu">
          {links.map((item) => <Link className={`nav-link ${isActive(pathname, item.href) ? "is-active" : ""}`} href={item.href} key={item.href}>{t(item.label)}</Link>)}
          <div className="relative" ref={categoryMenuRef}>
            <button className={`nav-link inline-flex items-center gap-1.5 ${pathname.startsWith("/category/") ? "is-active" : ""}`} type="button" onClick={() => setCategoriesOpen((value) => !value)} aria-expanded={categoriesOpen} aria-controls="desktop-category-menu">
              {t("nav.categories")} <span aria-hidden className={`text-xs transition ${categoriesOpen ? "rotate-180" : ""}`}>⌄</span>
            </button>
            {categoriesOpen ? <div id="desktop-category-menu" className="nav-category-menu">
              {categories.map((category) => <Link className="nav-category-link" href={categoryHref(category)} key={category.id} onClick={() => setCategoriesOpen(false)}>{category.name}</Link>)}
            </div> : null}
          </div>
        </nav>

        <div className="hidden items-center gap-2 lg:flex"><LanguageSwitch /><AuthActions /></div>
        <button className="nav-menu-toggle lg:hidden" onClick={() => setMenuOpen((value) => !value)} aria-expanded={menuOpen} aria-controls="mobile-menu" aria-label={menuOpen ? "Funga menyu" : "Fungua menyu"}><span aria-hidden>{menuOpen ? "×" : "☰"}</span></button>
      </div>

      {menuOpen ? <div id="mobile-menu" className="mobile-nav-layer lg:hidden" onPointerDown={(event) => { if (event.target === event.currentTarget) setMenuOpen(false); }}>
        <div className="mobile-nav-panel">
          <nav className="grid grid-cols-2 gap-2" aria-label="Urambazaji wa simu">
            {links.map((item) => <Link className={`mobile-nav-link ${isActive(pathname, item.href) ? "is-active" : ""}`} href={item.href} key={item.href} onClick={() => setMenuOpen(false)}>{t(item.label)}</Link>)}
            <Link className={`mobile-nav-link ${pathname.startsWith("/account") ? "is-active" : ""}`} href="/account" onClick={() => setMenuOpen(false)}>{t("nav.account")}</Link>
          </nav>
          <div className="mobile-nav-divider" />
          <p className="mobile-nav-label">{t("nav.categories")}</p>
          <div className="mobile-category-grid">
            {categories.slice(0, 8).map((category) => <Link href={categoryHref(category)} key={category.id} onClick={() => setMenuOpen(false)}>{category.name}</Link>)}
          </div>
          <div className="mobile-nav-divider" />
          <div className="flex items-center justify-between gap-3"><LanguageSwitch /><div className="flex min-w-0 justify-end"><AuthActions mobile /></div></div>
        </div>
      </div> : null}
    </header>
  );
}
