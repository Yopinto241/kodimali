"use client";
import { useEffect, useRef, useState } from "react";
import { UiText } from "@/components/ui-text";
import { SquareMediaVideo } from "@/components/square-media-video";
import { DirectMediaImage } from "@/components/direct-media-image";
import { promotionDestination, recordPromotion } from "@/lib/promotion-tracking";
import { useLanguage } from "@/components/language-provider";
import { sponsoredLayout } from "@/lib/sponsored-layout";
export type Promotion = { promotion_id: string; title: string; description?: string | null; cta_label?: string | null; target_url?: string | null; media_type?: string | null; media_url?: string | null; thumbnail_url?: string | null };
export function PromotionCard({ promotion }: { promotion: Promotion }) {
  const ref = useRef<HTMLElement>(null);
  const seen = useRef(false);
  const [broken, setBroken] = useState(false);
  useEffect(() => {
    const el = ref.current; if (!el || typeof IntersectionObserver === "undefined") return;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let visible = false;
    function schedule() {
      clearTimeout(timer);
      if (visible && !document.hidden && !seen.current) timer = setTimeout(() => {
        if (!visible || document.hidden || seen.current) return;
        seen.current = true; recordPromotion(promotion.promotion_id, "impression"); observer.disconnect();
      }, 1000);
    }
    const observer = new IntersectionObserver(([entry]) => {
      visible = entry.intersectionRatio >= 0.5; schedule();
    }, { threshold: [0, 0.5] });
    document.addEventListener("visibilitychange", schedule);
    observer.observe(el); return () => { clearTimeout(timer); observer.disconnect(); document.removeEventListener("visibilitychange", schedule); };
  }, [promotion.promotion_id]);
  const destination = promotionDestination(promotion.target_url);
  const external = /^https?:\/\//i.test(destination) && !/^https?:\/\/(www\.)?kodimali\.com(?:\/|$)/i.test(destination);
  return <article ref={ref} className="listing-card group sponsored-listing-card">
    <div className="listing-card-media">
      {promotion.media_url && !broken ? promotion.media_type === "video" ? <SquareMediaVideo src={promotion.media_url} poster={promotion.thumbnail_url} autoPlay controls onError={() => setBroken(true)} /> : <a href={destination} className="block h-full" rel="sponsored noopener noreferrer" target={external ? "_blank" : undefined} onClick={() => recordPromotion(promotion.promotion_id, "click")}><DirectMediaImage src={promotion.media_url} alt={promotion.title} sizes="(min-width:768px) 46vw, 92vw" className="listing-card-image" onError={() => setBroken(true)} /></a> : <div className="listing-card-empty"><UiText text="Sponsored by KODIMALI" /></div>}
      <div className="listing-card-badges sponsored-card-badge"><span><UiText text="Sponsored by KODIMALI" /></span></div>
    </div>
    <div className="sponsored-card-copy"><h3>{promotion.title}</h3>{promotion.description && <p>{promotion.description}</p>}
      <a className="btn btn-success" href={destination} rel="sponsored noopener noreferrer" target={external ? "_blank" : undefined} onClick={() => recordPromotion(promotion.promotion_id, "click")}><UiText text={promotion.target_url && destination !== "/listings" ? promotion.cta_label || "Open promotion" : "Browse listings"} /></a>
    </div>
  </article>;
}
export function PromotionStrip({ promotions }: { promotions: Promotion[] }) {
  const { language } = useLanguage();
  const { remaining } = sponsoredLayout(promotions, 0);
  if (!remaining.length) return null;
  const label = language === "sw" ? "Matangazo ya KODIMALI" : "KODIMALI promotions";
  return <section className="sponsored-listing-grid" aria-label={label}>
    <h2 className="font-heading text-xl font-semibold"><UiText text="Sponsored by KODIMALI" /></h2>
    {remaining.length > 1 && <p className="text-sm text-muted"><UiText text="Swipe or scroll sideways to see all sponsored ads." /></p>}
    <div className="sponsored-card-rail" tabIndex={0} role="region" aria-label={label}>{remaining.map((promotion) => <PromotionCard key={promotion.promotion_id} promotion={promotion} />)}</div>
  </section>;
}
