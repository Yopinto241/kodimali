/* eslint-disable @next/next/no-img-element */

import { SquareMediaVideo } from "@/components/square-media-video";

type Promotion = {
  promotion_id: string;
  title: string;
  description?: string | null;
  cta_label?: string | null;
  target_url?: string | null;
  media_type?: string | null;
  media_url?: string | null;
  thumbnail_url?: string | null;
};

export function PromotionStrip({
  promotions,
}: {
  promotions: Promotion[];
}) {
  if (promotions.length === 0) {
    return null;
  }

  return (
    <section className="py-4">
      <div className="flex snap-x snap-mandatory gap-4 overflow-x-auto scroll-smooth [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
        {promotions.map((promotion) => (
          <article
            key={promotion.promotion_id}
            className="surface-card w-full shrink-0 snap-center rounded-[20px] p-5 sm:p-6"
          >
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <p className="eyebrow">Platform promotion</p>
                <h3 className="mt-3 font-heading text-2xl font-semibold text-brand-ink">
                  {promotion.title}
                </h3>
              </div>
              <span className="status-badge status-info">
                {promotion.media_type ?? "promotion"}
              </span>
            </div>
            {promotion.media_url ? (
              <div className="mt-4 overflow-hidden rounded-[16px] border border-brand-border/70 bg-brand-card-soft">
                {promotion.media_type === "video" ? (
                  <SquareMediaVideo
                    src={promotion.media_url}
                    poster={promotion.thumbnail_url}
                  />
                ) : (
                  <img
                    src={promotion.media_url}
                    alt={promotion.title}
                    className="aspect-square w-full object-cover"
                  />
                )}
              </div>
            ) : null}
            {promotion.description ? (
              <p className="section-copy mt-4 text-sm">{promotion.description}</p>
            ) : null}
            <div className="mt-5 flex flex-wrap items-center gap-3">
              {promotion.target_url ? (
                <a
                  href={promotion.target_url}
                  className="btn btn-success"
                >
                  {promotion.cta_label || "Open"}
                </a>
              ) : null}
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}
