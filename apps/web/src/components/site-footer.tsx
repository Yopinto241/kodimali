"use client";

import Link from "next/link";
import { useLanguage } from "@/components/language-provider";

const quickLinks = [
  { href: "/", label: "footer.home" }, { href: "/listings", label: "footer.all" },
  { href: "/events", label: "nav.events" },
  { href: "/category/apartment", label: "footer.apartments" }, { href: "/category/house", label: "footer.houses" },
  { href: "/category/car", label: "footer.cars" }, { href: "/compare", label: "footer.compare" },
  { href: "/map", label: "footer.map" }, { href: "/advertise", label: "footer.advertise" },
  { href: "/download", label: "footer.download" }, { href: "/safety", label: "footer.safety" },
  { href: "/privacy", label: "footer.privacy" }, { href: "/terms", label: "footer.terms" },
  { href: "/delete-account", label: "footer.delete" },
] as const;

const supportLinks = [
  { href: "tel:0628621737", label: "Call us", value: "0628621737" },
  { href: "https://wa.me/255684684972", label: "WhatsApp", value: "0684684972" },
  { href: "https://instagram.com/kodimali1", label: "Instagram", value: "@kodimali1" },
  {
    href: "https://facebook.com/search/top?q=kodimali%20tanzania",
    label: "Facebook",
    value: "Kodimali",
  },
];

export function SiteFooter() {
  const { t } = useLanguage();
  return (
    <footer className="mt-16">
      <div className="app-shell pb-8">
        <div className="overflow-hidden rounded-[28px] border border-brand-border bg-[linear-gradient(145deg,rgba(11,31,58,0.98),rgba(18,43,74,0.95))] shadow-[0_24px_60px_rgba(11,31,58,0.18)]">
          <div className="grid gap-8 px-6 py-8 sm:px-8 lg:grid-cols-[1.2fr_0.8fr_0.9fr] lg:px-10 lg:py-10">
            <div>
              <p className="text-xs font-bold uppercase tracking-[0.24em] text-brand-green">
                Kodimali
              </p>
              <h2 className="mt-3 max-w-xl font-heading text-3xl font-semibold text-white sm:text-4xl">
                {t("footer.tagline")}
              </h2>
              <p className="mt-4 max-w-2xl text-sm leading-7 text-white/74">
                {t("footer.body")}
              </p>
              <div className="mt-6 flex flex-wrap gap-3">
                <Link href="/listings" className="btn btn-success">
                  {t("footer.browse")}
                </Link>
                <Link
                  href="/account"
                  className="inline-flex min-h-[44px] items-center justify-center rounded-full border border-white/18 bg-white/10 px-4 py-2 text-sm font-semibold text-white transition hover:bg-white/16"
                >
                  {t("footer.payment")}
                </Link>
                <Link
                  href="/manage"
                  className="inline-flex min-h-[44px] items-center justify-center rounded-full bg-brand-amber px-5 py-2 text-sm font-bold text-brand-navy transition hover:brightness-105"
                >
                  {t("footer.manage")}
                </Link>
              </div>
            </div>

            <div className="rounded-[22px] border border-brand-green/35 bg-black/15 p-5 shadow-inner">
              <p className="inline-flex rounded-full bg-brand-green px-3 py-1.5 text-sm font-extrabold uppercase tracking-[0.16em] text-white">
                {t("footer.links")}
              </p>
              <div className="mt-4 grid gap-2 sm:grid-cols-2 lg:grid-cols-1">
                {quickLinks.map((link) => (
                  <Link
                    key={link.href}
                    href={link.href}
                    className="footer-quick-link"
                  >
                    {t(link.label)}
                  </Link>
                ))}
              </div>
            </div>

            <div className="rounded-[22px] border border-white/10 bg-white/8 p-5">
              <p className="text-sm font-bold uppercase tracking-[0.2em] text-white/72">
                {t("footer.support")}
              </p>
              <div className="mt-4 grid gap-3">
                {supportLinks.map((link) => (
                  <a
                    key={link.label}
                    href={link.href}
                    target={link.href.startsWith("http") ? "_blank" : undefined}
                    rel={
                      link.href.startsWith("http")
                        ? "noreferrer noopener"
                        : undefined
                    }
                    className="rounded-2xl border border-white/10 bg-white/6 px-4 py-3 transition hover:bg-white/12"
                  >
                    <p className="text-xs font-bold uppercase tracking-[0.18em] text-white/56">
                      {link.label}
                    </p>
                    <p className="mt-1 text-sm font-semibold text-white">
                      {link.value}
                    </p>
                  </a>
                ))}
              </div>
            </div>
          </div>

          <div className="border-t border-white/10 px-6 py-4 sm:px-8 lg:px-10">
            <div className="flex flex-wrap items-center justify-between gap-3 text-sm text-white/62">
              <p>Copyright 2026 KODIMALI. All rights reserved.</p>
              <p>Built for East Africa rental discovery and verified agent connection.</p>
            </div>
          </div>
        </div>
      </div>
    </footer>
  );
}
