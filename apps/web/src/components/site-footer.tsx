import Link from "next/link";

const quickLinks = [
  { href: "/", label: "Home" },
  { href: "/listings", label: "All listings" },
  { href: "/category/apartment", label: "Apartments" },
  { href: "/category/house", label: "Houses" },
  { href: "/category/car", label: "Cars" },
  { href: "/manage", label: "Manage app" },
  { href: "/compare", label: "Compare listings" },
  { href: "/map", label: "Nearby map search" },
  { href: "/advertise", label: "Advertise with KODIMALI" },
  { href: "/download", label: "Download apps" },
  { href: "/safety", label: "Safety" },
  { href: "/privacy", label: "Privacy" },
  { href: "/terms", label: "Terms" },
  { href: "/delete-account", label: "Delete account" },
];

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
                Fast property discovery with trusted agent contact.
              </h2>
              <p className="mt-4 max-w-2xl text-sm leading-7 text-white/74">
                Browse listings, compare locations and prices, then unlock the
                right agent contact only when you are ready to move forward.
              </p>
              <div className="mt-6 flex flex-wrap gap-3">
                <Link href="/listings" className="btn btn-success">
                  Browse listings
                </Link>
                <Link
                  href="/account"
                  className="inline-flex min-h-[44px] items-center justify-center rounded-full border border-white/18 bg-white/10 px-4 py-2 text-sm font-semibold text-white transition hover:bg-white/16"
                >
                  How payment works
                </Link>
              </div>
            </div>

            <div className="rounded-[22px] border border-white/10 bg-white/8 p-5">
              <p className="text-sm font-bold uppercase tracking-[0.2em] text-white/72">
                Quick links
              </p>
              <div className="mt-4 grid gap-3">
                {quickLinks.map((link) => (
                  <Link
                    key={link.href}
                    href={link.href}
                    className="text-sm font-semibold text-white transition hover:text-brand-green"
                  >
                    {link.label}
                  </Link>
                ))}
              </div>
            </div>

            <div className="rounded-[22px] border border-white/10 bg-white/8 p-5">
              <p className="text-sm font-bold uppercase tracking-[0.2em] text-white/72">
                Support
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
