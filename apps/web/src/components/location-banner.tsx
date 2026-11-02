"use client";
import { ListingLocationFilter } from "@/components/listing-location-filter";
import { UiText } from "@/components/ui-text";
import { browserPreferences } from "@/lib/browser-preferences";

import { WardGpsFilter } from "@/components/ward-gps-filter";
import { useEffect, useState } from "react";

import { useLanguage } from "@/components/language-provider";

type LocationOption = { id: string; name: string };

export function LocationBanner({
  visibleByDefault,
  regions,
  persistent = false,
  initialLocation,
}: {
  visibleByDefault: boolean;
  regions: LocationOption[];
  persistent?: boolean;
  initialLocation?: { regionId?: string; districtId?: string; wardId?: string; areaId?: string };
}) {
  const { language } = useLanguage();
  const sw = language === "sw";
  // The initial client render must exactly match the server output. Browser-only
  // preferences are applied after hydration so localStorage cannot change the
  // shape of the hydrated tree.
  const [visible, setVisible] = useState(visibleByDefault);

  useEffect(() => {
    if (persistent) return;
    const timer = window.setTimeout(() => {
      const hiddenUntil = browserPreferences.getItem(
        "customer_location_banner_hidden_until",
      );
      if (hiddenUntil && Number(hiddenUntil) > Date.now()) {
        setVisible(false);
      }
    }, 0);
    return () => window.clearTimeout(timer);
  }, [persistent]);

  function skipBanner() {
    browserPreferences.setItem(
      "customer_location_banner_hidden_until",
      String(Date.now() + 3 * 24 * 60 * 60 * 1000),
    );
    setVisible(false);
  }

  if (!visible && !persistent) {
    return null;
  }

  return (
    <section className="location-picker rounded-[18px] p-4 sm:p-5">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="max-w-2xl">
          <h2 className="text-base font-bold text-[#183d34]"><UiText text={sw ? "Chagua eneo" : "Choose location"} /></h2>
          <p className="mt-1 text-sm text-[#61756e]"><UiText text={sw ? "Tumia GPS au chagua kwa hatua." : "Use GPS or choose step by step."} /></p>
        </div>
      </div>
      <div className="mt-4 flex flex-wrap gap-2">
        <WardGpsFilter />
        <ListingLocationFilter regions={regions} initialRegionId={initialLocation?.regionId} initialDistrictId={initialLocation?.districtId} initialWardId={initialLocation?.wardId} initialAreaId={initialLocation?.areaId} />
        {!persistent ? (
          <button
            type="button"
            onClick={skipBanner}
            className="btn btn-ghost"
          >
            <UiText text={sw ? "Ruka" : "Skip"} />
          </button>
        ) : null}
      </div>

    </section>
  );
}
