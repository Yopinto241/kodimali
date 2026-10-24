"use client";
import Link from "next/link";
import { useLanguage } from "@/components/language-provider";

const quickLinks = [
  { href: "/", label: "footer.home" }, { href: "/listings", label: "footer.all" },
  { href: "/events", label: "nav.events" }, { href: "/category/apartment", label: "footer.apartments" },
  { href: "/category/house", label: "footer.houses" }, { href: "/category/car", label: "footer.cars" },
  { href: "/compare", label: "footer.compare" }, { href: "/map", label: "footer.map" },
  { href: "/advertise", label: "footer.advertise" }, { href: "/download", label: "footer.download" },
  { href: "/safety", label: "footer.safety" }, { href: "/privacy", label: "footer.privacy" },
  { href: "/terms", label: "footer.terms" }, { href: "/delete-account", label: "footer.delete" },
] as const;

const supportLinks = [
  { href: "tel:0628621737", sw: "Piga simu", en: "Call", value: "0628621737" },
  { href: "https://wa.me/255684684972", sw: "WhatsApp", en: "WhatsApp", value: "0684684972" },
  { href: "https://instagram.com/kodimali1", sw: "Instagram", en: "Instagram", value: "@kodimali1" },
  { href: "https://facebook.com/search/top?q=kodimali%20tanzania", sw: "Facebook", en: "Facebook", value: "Kodimali" },
] as const;

export function SiteFooter() {
  const { t, language } = useLanguage();
  const sw = language === "sw";
  return <footer className="mt-8">
    <div className="app-shell pb-4">
      <div className="overflow-hidden rounded-2xl border border-brand-border bg-[linear-gradient(145deg,#0b1f3a,#17323a)] shadow-[0_14px_38px_rgba(11,31,58,.14)]">
        <div className="grid gap-5 px-5 py-5 lg:grid-cols-[.8fr_1.7fr_1fr] lg:items-start lg:px-7">
          <section>
            <p className="font-heading text-lg font-extrabold tracking-[.12em] text-white">KODIMALI</p>
            <p className="mt-1 max-w-sm text-sm font-semibold leading-5 text-white/88">{t("footer.tagline")}</p>
            <div className="mt-3 flex flex-wrap gap-2">
              <Link href="/listings" className="footer-action">{t("footer.browse")}</Link>
              <Link href="/account" className="footer-action">{t("footer.payment")}</Link>
              <Link href="/manage" className="footer-action footer-action-accent">{t("footer.manage")}</Link>
            </div>
          </section>

          <nav aria-label={t("footer.links")}>
            <p className="footer-heading">{t("footer.links")}</p>
            <div className="mt-2 grid grid-cols-2 gap-x-4 gap-y-1 sm:grid-cols-3 lg:grid-cols-4">
              {quickLinks.map((link) => <Link key={link.href} href={link.href} className="footer-quick-link">{t(link.label)}</Link>)}
            </div>
          </nav>

          <section>
            <p className="footer-heading">{t("footer.support")}</p>
            <div className="mt-2 grid grid-cols-2 gap-2">
              {supportLinks.map((link) => <a key={link.href} href={link.href} target={link.href.startsWith("http") ? "_blank" : undefined} rel={link.href.startsWith("http") ? "noreferrer noopener" : undefined} className="footer-contact"><span>{sw ? link.sw : link.en}</span><strong>{link.value}</strong></a>)}
            </div>
          </section>
        </div>
        <div className="flex flex-wrap items-center justify-between gap-1 border-t border-white/10 px-5 py-2 text-[11px] text-white/60 lg:px-7">
          <p>© 2026 KODIMALI. {sw ? "Haki zote zimehifadhiwa." : "All rights reserved."}</p>
          <p>{sw ? "Huduma za upangishaji Afrika Mashariki." : "Rental discovery across East Africa."}</p>
        </div>
      </div>
    </div>
  </footer>;
}
