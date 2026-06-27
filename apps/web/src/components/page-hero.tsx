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
    <section className="surface-card relative overflow-hidden px-6 py-6 sm:px-8 sm:py-8">
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 top-0 h-32 bg-[radial-gradient(circle_at_top_left,rgba(168,214,42,0.16),transparent_58%),linear-gradient(90deg,rgba(11,31,58,0.05),transparent)]"
      />
      <div
        className={`relative grid gap-6 ${
          aside ? "lg:grid-cols-[minmax(0,1fr)_320px] lg:items-start" : ""
        }`}
      >
        <div>
          <p className="eyebrow">{eyebrow}</p>
          <h1 className="mt-3 max-w-4xl font-heading text-4xl font-semibold tracking-tight text-brand-ink sm:text-5xl">
            {title}
          </h1>
          <p className="section-copy mt-4 max-w-3xl text-base sm:text-lg">
            {description}
          </p>
          {actions ? <div className="mt-6 flex flex-wrap gap-3">{actions}</div> : null}
        </div>
        {aside ? <div className="soft-panel p-5 sm:p-6">{aside}</div> : null}
      </div>
    </section>
  );
}
