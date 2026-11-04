"use client";
import { safeUserMessage } from "@/lib/user-message";
import { UiInput, UiText } from "@/components/ui-text";

import { useCallback, useEffect, useRef, useState } from "react";

import { browserPreferences } from "@/lib/browser-preferences";
import { whatsAppUrl } from "@/lib/whatsapp";
import { useListingAccess } from "@/lib/listing-access";
import { StatusPill } from "@/components/status-pill";
import Link from "next/link";
import { useLanguage } from "@/components/language-provider";

type AgentSummary = {
  id?: string | null;
  display_name?: string | null;
  business_name?: string | null;
  phone_number?: string | null;
  location_label?: string | null;
  verification_status?: string | null;
};

type PaymentSession = {
  payment_id?: string | null;
  access_token?: string | null;
  amount?: number | string | null;
  currency?: string | null;
  status?: string | null;
  payment_method?: string | null;
  customer_phone_number?: string | null;
  phone_number?: string | null;
  access_expires_at?: string | null;
  message?: string | null;
};

const pollableStatuses = new Set(["", "pending", "processing"]);

function storageKey(listingId: string) {
  return `kodimali-web-contact-access:${listingId}`;
}

function readableError(error: unknown) {
  if (error instanceof Error && safeUserMessage(error).trim().length > 0) {
    return safeUserMessage(error);
  }
  return "Something went wrong. Please try again.";
}

export function AgentContactCard({
  listingId,
  agentSummary,
}: {
  listingId: string;
  agentSummary?: AgentSummary | null;
}) {
  const { access, error: accessError, refresh } = useListingAccess(listingId, "contact");
  const { language } = useLanguage();
  const sw = language === "sw";
  const [customerName, setCustomerName] = useState("");
  const [customerPhoneNumber, setCustomerPhoneNumber] = useState("");
  const [session, setSession] = useState<PaymentSession | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [checking, setChecking] = useState(false);
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const expiry=Date.parse(session?.access_expires_at ?? "");
    if(!Number.isFinite(expiry)) return;
    const timer=window.setTimeout(()=>setNow(Date.now()),Math.min(2147483647,Math.max(0,expiry-Date.now())+10));
    return()=>window.clearTimeout(timer);
  },[session?.access_expires_at]);
  const whatsappIntent = useRef(false);
  const redirected = useRef(false);
  const validated = useRef<string | undefined>(undefined);

  useEffect(() => {
    whatsappIntent.current = new URLSearchParams(window.location.search).get("intent") === "whatsapp";
    const timer = window.setTimeout(() => {
      const raw = browserPreferences.getItem(storageKey(listingId));
      if (!raw) return;
      try {
        const saved = JSON.parse(raw) as PaymentSession;
        setSession({ ...saved, phone_number: null });
        setMessage(typeof saved.message === "string" ? saved.message : null);
      } catch {
        browserPreferences.removeItem(storageKey(listingId));
      }
    }, 0);
    return () => window.clearTimeout(timer);
  }, [listingId]);

  const sessionValid = session?.access_expires_at && Date.parse(session.access_expires_at) > now;
  const unlockedPhone = (access?.phone ?? (sessionValid ? session?.phone_number : null) ?? "").trim();
  const verified = agentSummary?.verification_status === "approved";
  const displayName =
    agentSummary?.display_name?.trim() ||
    agentSummary?.business_name?.trim() ||
    "Agent";

  const persistSession = useCallback(
    (next: PaymentSession | null) => {
      setSession(next);
      if (typeof window === "undefined") {
        return;
      }
      if (!next) {
        browserPreferences.removeItem(storageKey(listingId));
        return;
      }
      browserPreferences.setItem(storageKey(listingId), JSON.stringify(next));
    },
    [listingId],
  );

  async function startPayment() {
    if (customerName.trim().length < 2) {
      setMessage("Enter your full name before continuing.");
      return;
    }
    if (customerPhoneNumber.trim().length < 8) {
      setMessage("Enter a valid phone number before continuing.");
      return;
    }

    setSubmitting(true);
    setMessage(null);
    try {
      const response = await fetch("/api/listing-contact-payment", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          listing_id: listingId,
          customer_name: customerName.trim(),
          customer_phone_number: customerPhoneNumber.trim(),
          expected_amount: access?.contactPrice,
        }),
      });
      const payload = (await response.json()) as Record<string, unknown>;
      if (!response.ok) {
        throw new Error(
          String(payload.error ?? "Could not start the payment."),
        );
      }

      const nextSession: PaymentSession = {
        payment_id: payload.paymentId as string | undefined,
        access_token: payload.accessToken as string | undefined,
        amount: payload.amount as number | string | undefined,
        currency: payload.currency as string | undefined,
        status: payload.paymentStatus as string | undefined,
        payment_method: payload.paymentMethod as string | undefined,
        customer_phone_number: customerPhoneNumber.trim(),
        phone_number: (payload.phoneNumber as string | undefined) ?? null,
        access_expires_at: payload.accessExpiresAt as string | undefined,
        message: payload.message as string | undefined,
      };
      persistSession(nextSession);
      setMessage((payload.message as string | undefined) ?? null);
    } catch (error) {
      setMessage(readableError(error));
      refresh();
    } finally {
      setSubmitting(false);
    }
  }

  const checkPayment = useCallback(
    async (silent = false) => {
      if (!session?.payment_id || !session.access_token || checking) {
        return;
      }
      if (!silent) {
        setMessage(null);
      }
      setChecking(true);
      try {
        const response = await fetch("/api/listing-contact-payment/status", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            payment_id: session.payment_id,
            access_token: session.access_token,
          }),
        });
        const payload = (await response.json()) as Record<string, unknown>;
        if (!response.ok) {
          throw new Error(
            String(payload.error ?? "Could not verify the payment."),
          );
        }

        const nextSession: PaymentSession = {
          ...session,
          status:
            (payload.paymentStatus as string | undefined) ?? session.status,
          phone_number:
            (payload.phoneNumber as string | undefined) ?? null,
          access_expires_at: payload.accessExpiresAt as string | undefined,
          message: payload.message as string | undefined,
        };
        persistSession(nextSession);
        setMessage((payload.message as string | undefined) ?? null);
      } catch (error) {
        if (!silent) {
          setMessage(readableError(error));
        }
      } finally {
        setChecking(false);
      }
    },
    [checking, persistSession, session],
  );

  useEffect(() => {
    if (!session) {
      return;
    }
    const status = (session.status ?? "").trim().toLowerCase();
    const phoneNumber = (session.phone_number ?? "").trim();
    if (phoneNumber || !pollableStatuses.has(status)) {
      return;
    }
    const timer = window.setInterval(() => {
      void checkPayment(true);
    }, 6000);
    return () => window.clearInterval(timer);
  }, [checkPayment, session]);

  useEffect(() => {
    if (session?.payment_id && session.access_token && validated.current !== session.payment_id) {
      validated.current = session.payment_id;
      void checkPayment(true);
    }
  }, [session, checkPayment]);

  useEffect(() => {
    const destination = whatsAppUrl(unlockedPhone);
    if (!whatsappIntent.current || redirected.current || !destination) return;
    redirected.current = true;
    const current = new URL(window.location.href);
    current.searchParams.delete("intent");
    window.history.replaceState(window.history.state, "", `${current.pathname}${current.search}`);
    window.location.assign(destination);
  }, [unlockedPhone]);

  function resetSession() {
    persistSession(null);
    setMessage(null);
  }

  return (
    <div className="listing-agent-card surface-card rounded-[20px] p-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="eyebrow"><UiText text={sw ? "Wakala" : "Agent"} /></p>
          <h2 className="mt-3 font-heading text-2xl font-semibold text-brand-ink">
            {displayName}
          </h2>
          <p className="section-copy mt-2 text-sm">
            {agentSummary?.location_label?.trim() || "Location not shared yet"}
          </p>
          {agentSummary?.id ? (
            <Link
              className="mt-2 inline-block text-sm font-bold text-brand-navy underline"
              href={`/agent/${agentSummary.id}`}
            >
              <UiText text={sw ? "Wasifu wa wakala" : "Agent profile"} />
            </Link>
          ) : null}
        </div>
        <StatusPill
          label={verified ? "Verified agent" : "Verification pending"}
          tone={verified ? "active" : "pending"}
        />
      </div>

      {unlockedPhone ? (
        <div className="soft-panel mt-5 p-5">
          <p className="eyebrow"><UiText text={"Phone number"} /></p>
          <a href={whatsAppUrl(unlockedPhone) ?? undefined} className="mt-3 inline-flex items-center gap-2 text-2xl font-bold text-brand-navy" aria-label={`WhatsApp ${unlockedPhone}`}>
            <svg viewBox="0 0 24 24" aria-hidden="true" className="size-6 shrink-0 text-[#075e54]" fill="none"><path d="M20 11.7a8 8 0 0 1-11.8 7L4 20l1.3-4.1A8 8 0 1 1 20 11.7Z" stroke="currentColor" strokeWidth="1.8"/><path d="M9 7.8c-.6 0-1 .8-1 1.4 0 2.5 3.3 5.8 5.8 5.8.7 0 1.5-.4 1.5-1l-2-1-1 1c-1.1-.5-2.6-2-3.1-3.1l1-1-1.2-2.1Z" fill="currentColor"/></svg>{unlockedPhone}
          </a>
          <div className="mt-4 flex flex-wrap gap-3">
            <a href={`tel:${unlockedPhone}`} className="btn btn-success"><UiText text={"Call agent"} /></a>
            <a
              href={whatsAppUrl(unlockedPhone) ?? undefined}
              target="_blank"
              rel="noreferrer"
              className="btn btn-outline"
            >
              WhatsApp
            </a>
          </div>
        </div>
      ) : !access ? (
        <div className="mt-5" role="status"><p>{accessError ? (sw ? "Imeshindikana kuangalia mawasiliano." : "Contact access could not be checked.") : (sw ? "Inaangalia mawasiliano..." : "Checking contact access...")}</p>{accessError && <button className="btn btn-outline mt-3" onClick={refresh}>{sw ? "Jaribu tena" : "Try again"}</button>}</div>
      ) : session ? (
        <div className="soft-panel mt-5 p-5">
          <p className="text-lg font-semibold text-brand-ink"><UiText text={"Amount:"} />{session.amount ?? "-"} {session.currency ?? "TZS"}
          </p>
          <p className="section-copy mt-3 text-sm">
            {message ??
              "Approve the request on your phone. Your contact options will be ready after confirmation."}
          </p>
          {session.payment_method ? (
            <p className="mt-3 text-sm font-semibold text-brand-ink"><UiText text={"Payment method:"} />{session.payment_method}
            </p>
          ) : null}
          {session.customer_phone_number ? (
            <p className="field-help mt-2"><UiText text={"Payment prompt sent to"} />{session.customer_phone_number}.
            </p>
          ) : null}
          <div className="mt-5 flex flex-wrap gap-3">
            <button
              type="button"
              onClick={() => void checkPayment(false)}
              disabled={checking}
              className="btn btn-outline"
            >
              <UiText text={checking ? "Checking..." : "Check payment now"} />
            </button>
            {(["failed","expired","cancelled"].includes(session.status ?? "") || (session.access_expires_at && !sessionValid)) && <button
              type="button"
              onClick={resetSession}
              className="btn btn-ghost"
            ><UiText text={"Start a new payment"} /></button>}
          </div>
        </div>
      ) : (
        <div className="mt-5 grid gap-4">
          <div className="rounded-2xl border border-[#b9e5d5] bg-[#e7f7f1] p-3 text-sm text-[#31564c]">
            <UiText text={sw ? "Mawasiliano yanapatikana kwa saa 24 baada ya malipo. Ada hii si malipo ya nafasi." : "Contact access lasts 24 hours after payment. This is separate from a booking payment."} />
          </div>
          <p className="section-copy text-sm">
            <UiText text={sw
              ? `Ada ya mara moja: TZS ${access.contactPrice?.toLocaleString()}. Endelea kwa simu au WhatsApp.`
              : `One-time fee: TZS ${access.contactPrice?.toLocaleString()}. Continue by phone or WhatsApp.`} />
          </p>
          <label className="grid gap-2">
            <span className="field-label"><UiText text={"Full name"} /></span>
            <UiInput
              value={customerName}
              onChange={(event) => setCustomerName(event.target.value)}
              className="field-input"
              placeholder="Mfano: Amina Said"
            />
          </label>
          <label className="grid gap-2">
            <span className="field-label"><UiText text={"Phone number"} /></span>
            <UiInput
              value={customerPhoneNumber}
              onChange={(event) => setCustomerPhoneNumber(event.target.value)}
              className="field-input"
              placeholder="Mfano: 2557XXXXXXXX"
            />
          </label>
          <button
            type="button"
            onClick={() => void startPayment()}
            disabled={submitting}
            className="btn btn-success"
          >
            <UiText text={submitting ? "Sending request..." : (sw ? `Lipa TZS ${access.contactPrice?.toLocaleString()} na uendelee` : `Pay TZS ${access.contactPrice?.toLocaleString()} and continue`)} />
          </button>
        </div>
      )}

      {message ? <p className="mt-4 text-sm text-muted"><UiText text={message} /></p> : null}
    </div>
  );
}
