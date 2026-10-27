"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { getBrowserSupabase } from "@/lib/supabase-browser";
import { useLanguage } from "@/components/language-provider";

const comparisonKey = "kodimali-comparison-listings";

export function ListingActions({
  listingId,
  bookingHref,
  bookingMode,
}: {
  listingId: string;
  bookingHref?: string;
  bookingMode?: "not_bookable" | "request_booking" | "instant_booking";
}) {
  const supabase = useMemo(() => getBrowserSupabase(), []);
  const router = useRouter();
  const { language } = useLanguage();
  const sw = language === "sw";
  const [saved, setSaved] = useState(false);
  const [compared, setCompared] = useState(false);
  const [priceAlert, setPriceAlert] = useState(false);
  const [message, setMessage] = useState("");

  useEffect(() => {
    const ids = JSON.parse(
      localStorage.getItem(comparisonKey) || "[]",
    ) as string[];
    queueMicrotask(() => setCompared(ids.includes(listingId)));
    void supabase.auth.getUser().then(async ({ data }) => {
      if (!data.user) return;
      const result = await supabase
        .from("customer_saved_listings")
        .select("listing_id")
        .eq("customer_id", data.user.id)
        .eq("listing_id", listingId)
        .maybeSingle();
      setSaved(Boolean(result.data));
      const alert = await supabase.from("price_alerts").select("is_active").eq("user_id", data.user.id).eq("listing_id", listingId).maybeSingle();
      setPriceAlert(Boolean((alert.data as { is_active?: boolean } | null)?.is_active));
    });
  }, [listingId, supabase]);

  async function toggleSaved() {
    const { data } = await supabase.auth.getUser();
    if (!data.user) {
      setMessage(
        "Sign in from Customer Account to synchronize saved listings.",
      );
      return;
    }
    const next = !saved;
    const result = await supabase.rpc("set_listing_saved", {
      p_listing_id: listingId,
      p_saved: next,
    } as never);
    if (result.error) setMessage(result.error.message);
    else {
      setSaved(next);
      setMessage(next ? "Listing saved." : "Listing removed.");
    }
  }

  async function createPriceAlert() {
    const { data } = await supabase.auth.getUser();
    if (!data.user) {
      router.push(`/login?next=${encodeURIComponent(window.location.pathname)}&action=price-alert`);
      return;
    }
    const result = await supabase.from("price_alerts").upsert(
      {
        user_id: data.user.id,
        listing_id: listingId,
        is_active: !priceAlert,
      } as never,
      { onConflict: "user_id,listing_id" },
    );
    if (!result.error) setPriceAlert(!priceAlert);
    setMessage(result.error?.message ?? (!priceAlert ? "Price-drop alert enabled." : "Price-drop alert disabled."));
  }

  function toggleCompared() {
    const current = JSON.parse(
      localStorage.getItem(comparisonKey) || "[]",
    ) as string[];
    const next = current.includes(listingId)
      ? current.filter((id) => id !== listingId)
      : [...current, listingId].slice(-4);
    localStorage.setItem(comparisonKey, JSON.stringify(next));
    setCompared(next.includes(listingId));
    setMessage(
      next.includes(listingId)
        ? "Added to comparison."
        : "Removed from comparison.",
    );
  }

  return (
    <div className="mt-4" onClick={(event) => event.stopPropagation()}>
      <div className="flex flex-wrap gap-2">
        {bookingHref ? (
          <Link
            href={bookingHref}
            className="btn btn-success !min-h-9 !px-3 !py-2 text-xs"
          >
            {bookingMode === "instant_booking"
              ? sw
                ? "Book sasa"
                : "Book Now"
              : sw
                ? "Tuma booking"
                : "Request Booking"}
          </Link>
        ) : null}
        <button
          type="button"
          className="btn btn-outline !min-h-9 !px-3 !py-2 text-xs"
          onClick={() => void toggleSaved()}
        >
          {saved ? (sw ? "Imehifadhiwa" : "Saved") : sw ? "Hifadhi" : "Save"}
        </button>
        <button
          type="button"
          className="btn btn-outline !min-h-9 !px-3 !py-2 text-xs"
          onClick={toggleCompared}
        >
          {compared
            ? sw
              ? "Inalinganishwa"
              : "Comparing"
            : sw
              ? "Linganisha"
              : "Compare"}
        </button>
        <button
          type="button"
          className="btn btn-outline !min-h-9 !px-3 !py-2 text-xs"
          onClick={() => void createPriceAlert()}
        >
          {priceAlert ? (sw ? "Bei: imewashwa" : "Alert: on") : (sw ? "Taarifa ya bei" : "Price alert")}
        </button>
        <Link
          href="/compare"
          className="btn btn-ghost !min-h-9 !px-3 !py-2 text-xs"
        >
          {sw ? "Angalia ulinganisho" : "View comparison"}
        </Link>
      </div>
      {message ? (
        <p className="mt-2 text-xs text-muted" role="status">
          {message}
        </p>
      ) : null}
    </div>
  );
}

export function ListingViewRecorder({ listingId }: { listingId: string }) {
  const supabase = useMemo(() => getBrowserSupabase(), []);
  useEffect(() => {
    const recent = JSON.parse(
      localStorage.getItem("kodimali-recent-listings") || "[]",
    ) as string[];
    localStorage.setItem(
      "kodimali-recent-listings",
      JSON.stringify(
        [listingId, ...recent.filter((id) => id !== listingId)].slice(0, 12),
      ),
    );
    void supabase.auth.getUser().then(({ data }) => {
      if (data.user)
        void supabase.rpc("record_listing_view", {
          p_listing_id: listingId,
        } as never);
    });
    void supabase.rpc("track_business_event", {
      p_event_type: "listing_view",
      p_listing_id: listingId,
      p_metadata: { surface: "website" },
    } as never);
  }, [listingId, supabase]);
  return null;
}
