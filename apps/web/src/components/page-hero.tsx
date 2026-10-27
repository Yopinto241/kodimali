import type { ReactNode } from "react";

type PageHeroProps = {
  eyebrow: string;
  title: string;
  description: string;
  actions?: ReactNode;
  aside?: ReactNode;
};

export function PageHero({
  eyebrow,
  title,
  description,
  actions,
  aside,
}: PageHeroProps) {
  return (
    <section className="page-hero-card surface-card relative min-w-0 overflow-hidden px-4 py-5 sm:px-7 sm:py-6">
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 top-0 h-32 bg-[radial-gradient(circle_at_top_left,rgba(168,214,42,0.16),transparent_58%),linear-gradient(90deg,rgba(11,31,58,0.05),transparent)]"
      />
      <div
        className={`relative grid min-w-0 gap-6 ${
          aside ? "lg:grid-cols-[minmax(0,1fr)_320px] lg:items-start" : ""
        }`}
      >
        <div className="min-w-0">
          <p className="eyebrow">{eyebrow}</p>
          <h1 className="mt-2 max-w-4xl break-words font-heading text-3xl font-semibold tracking-tight text-brand-ink sm:text-4xl">
            {title}
          </h1>
          <p className="section-copy mt-3 line-clamp-2 max-w-3xl text-sm sm:text-base">
            {description}
          </p>
          {actions ? <div className="mt-4 flex flex-wrap gap-2">{actions}</div> : null}
        </div>
        {aside ? <div className="soft-panel min-w-0 p-4 sm:p-6">{aside}</div> : null}
      </div>
    </section>
  );
}
