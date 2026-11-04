"use client";
import { safeUserMessage } from "@/lib/user-message";
import { UiButton, UiText } from "@/components/ui-text";
import { browserPreferences, readStoredIds } from "@/lib/browser-preferences";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "@/components/navigation-progress";
import { getBrowserSupabase } from "@/lib/supabase-browser";
import { useLanguage } from "@/components/language-provider";

const comparisonKey = "kodimali-comparison-listings";

export function ListingActions({
  listingId,
  bookingHref,
  bookingMode,
  hasWhatsApp = false,
}: {
  listingId: string;
  bookingHref?: string;
  bookingMode?: "not_bookable" | "request_booking" | "instant_booking";
  hasWhatsApp?: boolean;
}) {
  const supabase = useMemo(() => getBrowserSupabase(), []);
  const navigate = useNavigate();
  const { language } = useLanguage();
  const sw = language === "sw";
  const [saved, setSaved] = useState(false);
  const [compared, setCompared] = useState(false);
  const [priceAlert, setPriceAlert] = useState(false);
  const [message, setMessage] = useState("");

  useEffect(() => {
    const ids = readStoredIds(comparisonKey);
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
    if (result.error) setMessage(safeUserMessage(result.error));
    else {
      setSaved(next);
      setMessage(next ? "Listing saved." : "Listing removed.");
    }
  }

  async function createPriceAlert() {
    const { data } = await supabase.auth.getUser();
    if (!data.user) {
      navigate(`/login?next=${encodeURIComponent(window.location.pathname)}&action=price-alert`);
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
    setMessage((result.error?.message ? safeUserMessage(result.error?.message) : null) ?? (!priceAlert ? "Price-drop alert enabled." : "Price-drop alert disabled."));
  }

  function toggleCompared() {
    const current = readStoredIds(comparisonKey);
    const next = current.includes(listingId)
      ? current.filter((id) => id !== listingId)
      : [...current, listingId].slice(-4);
    if (!browserPreferences.setItem(comparisonKey, JSON.stringify(next))) { setMessage(sw ? "Kivinjari kimezuia kuhifadhi ulinganisho." : "Your browser has blocked saving comparisons."); return; }
    setCompared(next.includes(listingId));
    setMessage(
      next.includes(listingId)
        ? "Added to comparison."
        : "Removed from comparison.",
    );
  }

  return (
    <div onClick={(event) => event.stopPropagation()}>
      <div className="flex flex-wrap gap-2">
        {hasWhatsApp && <Link href={`/listing/${listingId}/contact?intent=whatsapp`} className="listing-icon-action listing-whatsapp-action" aria-label={sw ? "Fungua WhatsApp ya wakala" : "Unlock agent WhatsApp"} title={sw ? "Fungua WhatsApp ya wakala" : "Unlock agent WhatsApp"}>
          <svg viewBox="0 0 24 24" aria-hidden="true" fill="none"><path d="M20 11.7a8 8 0 0 1-11.8 7L4 20l1.3-4.1A8 8 0 1 1 20 11.7Z" stroke="currentColor" strokeWidth="1.8"/><path d="M9 7.8c-.6 0-1 .8-1 1.4 0 2.5 3.3 5.8 5.8 5.8.7 0 1.5-.4 1.5-1l-2-1-1 1c-1.1-.5-2.6-2-3.1-3.1l1-1-1.2-2.1Z" fill="currentColor"/></svg>
        </Link>}
        {bookingHref ? (
          <Link
            href={bookingHref}
            className="btn btn-success !min-h-9 !px-3 !py-2 text-xs"
          >
            <UiText text={bookingMode === "instant_booking"
              ? sw
                ? "Book sasa"
                : "Book Now"
              : sw
                ? "Tuma booking"
                : "Request Booking"} />
          </Link>
        ) : null}
        <UiButton
          type="button"
          className={`listing-icon-action ${saved ? "active" : ""}`}
          onClick={() => void toggleSaved()}
          aria-label={saved ? (sw ? "Ondoa hifadhi" : "Remove saved listing") : (sw ? "Hifadhi" : "Save")}
          title={saved ? (sw ? "Imehifadhiwa" : "Saved") : (sw ? "Hifadhi" : "Save")}
        >
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 4.5A1.5 1.5 0 0 1 7.5 3h9A1.5 1.5 0 0 1 18 4.5V21l-6-4-6 4V4.5Z" /></svg>
        </UiButton>
        <button
          type="button"
          className="btn btn-outline !min-h-9 !px-3 !py-2 text-xs"
          onClick={toggleCompared}
        >
          <UiText text={compared
            ? sw
              ? "Inalinganishwa"
              : "Comparing"
            : sw
              ? "Linganisha"
              : "Compare"} />
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
          <UiText text={sw ? "Angalia ulinganisho" : "View comparison"} />
        </Link>
      </div>
      {message ? (
        <p className="mt-2 text-xs text-muted" role="status">
          <UiText text={message} />
        </p>
      ) : null}
    </div>
  );
}

export function ListingViewRecorder({ listingId }: { listingId: string }) {
  const supabase = useMemo(() => getBrowserSupabase(), []);
  useEffect(() => {
    const recent = readStoredIds("kodimali-recent-listings");
    browserPreferences.setItem(
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
