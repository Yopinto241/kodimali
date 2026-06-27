"use client";

import { useId } from "react";
import Script from "next/script";

declare global {
  interface Window {
    adsbygoogle?: unknown[];
  }
}

type SlotKind = "home" | "category" | "detail";

export function GoogleAdSlot({
  slot,
  clientId,
  slotId,
}: {
  slot: SlotKind;
  clientId: string;
  slotId: string;
}) {
  const scriptId = useId().replace(/:/g, "-");

  if (!clientId || !slotId) {
    return null;
  }

  return (
    <section className="py-4">
      <Script
        id={`adsbygoogle-${slot}-${scriptId}`}
        strategy="afterInteractive"
        src={`https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${clientId}`}
        crossOrigin="anonymous"
      />
      <div className="surface-card rounded-[20px] p-5">
        <p className="eyebrow">Ads by Google</p>
        <ins
          className="adsbygoogle"
          style={{ display: "block" }}
          data-ad-client={clientId}
          data-ad-slot={slotId}
          data-ad-format="auto"
          data-full-width-responsive="true"
          ref={(element) => {
            if (!element || typeof window === "undefined") {
              return;
            }
            try {
              (window.adsbygoogle = window.adsbygoogle || []).push({});
            } catch {
              return;
            }
          }}
        />
      </div>
    </section>
  );
}
