import Image from "next/image";
import Link from "next/link";

import { fetchCategories } from "@/lib/supabase-public";

const primaryNavItems = [
  { href: "/", label: "Home" },
  { href: "/category/apartment", label: "Apartment" },
  { href: "/listings", label: "All listings" },
  { href: "/account", label: "Customer account" },
  { href: "/safety", label: "Safety" },
  { href: "/manage", label: "Manage" },
];

export async function SiteHeader() {
  const categories = (await fetchCategories()) as Array<{
    id: string;
    slug: string;
    name: string;
  }>;
  const categoriesWithApartment = categories.some(
    (category) => category.slug === "apartment",
  )
    ? categories
    : [
        {
          id: "apartment-fallback",
          slug: "apartment",
          name: "Apartment",
        },
        ...categories,
      ];
  const sortedCategories = [
    ...categoriesWithApartment.filter((category) => category.slug === "apartment"),
    ...categoriesWithApartment.filter((category) => category.slug !== "apartment"),
  ];

  return (
    <header className="sticky top-0 z-50 border-b border-brand-border bg-white/92 shadow-[0_18px_40px_rgba(11,31,58,0.08)] backdrop-blur-xl">
      <div className="app-shell">
        <div className="flex min-h-[84px] flex-col justify-center gap-4 py-4">
          <div className="flex items-center justify-between gap-4">
            <Link href="/" className="flex min-w-0 items-center gap-3">
              <div className="flex h-12 w-12 items-center justify-center overflow-hidden rounded-2xl border border-brand-border bg-white shadow-[0_12px_28px_rgba(11,31,58,0.08)]">
                <Image
                  src="/icon.png"
                  alt="Kodimali"
                  width={40}
                  height={40}
                  priority
                  className="h-10 w-10 object-contain"
                />
              </div>
              <div className="min-w-0">
                <p className="text-lg font-black tracking-[0.2em] text-brand-navy">
                  KODIMALI
                </p>
                <p className="truncate text-sm text-muted">
                  Trusted rental marketplace
                </p>
              </div>
            </Link>

            <nav
              aria-label="Primary"
              className="hidden items-center justify-end rounded-full border border-[#0b1f3a]/20 bg-white px-1 py-1 shadow-[0_12px_28px_rgba(11,31,58,0.10)] lg:flex"
            >
              {primaryNavItems.map((item) => (
                <Link
                  key={item.href}
                  href={item.href}
                  className="rounded-full border border-transparent px-4 py-2 text-sm font-bold text-[#0b1f3a] transition hover:bg-[#eaf4d2] hover:text-[#0b1f3a]"
                >
                  {item.label}
                </Link>
              ))}
            </nav>
          </div>

          <nav
            aria-label="Primary mobile"
            className="-mx-1 flex gap-2 overflow-x-auto px-1 pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden lg:hidden"
          >
            {primaryNavItems.map((item) => (
              <Link
                key={item.href}
                href={item.href}
                className="shrink-0 rounded-full border border-[#0b1f3a]/20 bg-white px-4 py-2 text-sm font-bold text-[#0b1f3a] shadow-sm"
              >
                {item.label}
              </Link>
            ))}
          </nav>

          <nav aria-label="Categories" className="flex flex-col gap-2">
            <div className="flex items-center justify-between gap-3">
              <p className="text-xs font-bold uppercase tracking-[0.22em] text-brand-navy/72">
                Browse categories
              </p>
              <Link
                href="/listings"
                className="text-sm font-semibold text-brand-navy transition hover:text-brand-ink"
              >
                View all listings
              </Link>
            </div>
            <div className="-mx-1 flex gap-2 overflow-x-auto rounded-[20px] bg-brand-navy-surface/8 px-3 py-3 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
              <Link
                href="/listings"
                className="shrink-0 rounded-full border border-brand-navy bg-brand-navy px-4 py-2 text-sm font-semibold text-white shadow-[0_10px_22px_rgba(11,31,58,0.12)] transition hover:bg-brand-navy-surface"
              >
                All
              </Link>
              {sortedCategories.map((category) => (
                <Link
                  key={category.id}
                  href={`/category/${category.slug}`}
                  className={`shrink-0 rounded-full border px-4 py-2 text-sm font-semibold transition ${
                    category.slug === "apartment"
                      ? "border-brand-green bg-brand-green text-brand-navy shadow-[0_10px_22px_rgba(145,191,17,0.28)] hover:bg-brand-green"
                      : "border-brand-navy bg-brand-navy-surface text-white shadow-[0_10px_22px_rgba(11,31,58,0.16)] hover:bg-brand-navy"
                  }`}
                >
                  {category.name}
                </Link>
              ))}
            </div>
          </nav>
        </div>
      </div>
    </header>
  );
}
