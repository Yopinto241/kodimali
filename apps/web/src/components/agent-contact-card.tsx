"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

import { StatusPill } from "@/components/status-pill";

type AgentSummary = {
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
  message?: string | null;
};

const pollableStatuses = new Set(["", "pending", "processing"]);

function storageKey(listingId: string) {
  return `kodimali-web-contact-access:${listingId}`;
}

function readableError(error: unknown) {
  if (error instanceof Error && error.message.trim().length > 0) {
    return error.message;
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
  const initialSession =
    typeof window === "undefined"
      ? null
      : (() => {
          const raw = window.localStorage.getItem(storageKey(listingId));
          if (!raw) {
            return null;
          }
          try {
            return JSON.parse(raw) as PaymentSession;
          } catch {
            window.localStorage.removeItem(storageKey(listingId));
            return null;
          }
        })();
  const [customerName, setCustomerName] = useState("");
  const [customerPhoneNumber, setCustomerPhoneNumber] = useState("");
  const [session, setSession] = useState<PaymentSession | null>(initialSession);
  const [message, setMessage] = useState<string | null>(
    typeof initialSession?.message === "string" ? initialSession.message : null,
  );
  const [submitting, setSubmitting] = useState(false);
  const [checking, setChecking] = useState(false);

  const unlockedPhone = useMemo(
    () => (agentSummary?.phone_number ?? session?.phone_number ?? "").trim(),
    [agentSummary?.phone_number, session],
  );
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
        window.localStorage.removeItem(storageKey(listingId));
        return;
      }
      window.localStorage.setItem(storageKey(listingId), JSON.stringify(next));
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
        }),
      });
      const payload = (await response.json()) as Record<string, unknown>;
      if (!response.ok) {
        throw new Error(String(payload.error ?? "Could not start the payment."));
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
        message: payload.message as string | undefined,
      };
      persistSession(nextSession);
      setMessage((payload.message as string | undefined) ?? null);
    } catch (error) {
      setMessage(readableError(error));
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
          throw new Error(String(payload.error ?? "Could not verify the payment."));
        }

        const nextSession: PaymentSession = {
          ...session,
          status: (payload.paymentStatus as string | undefined) ?? session.status,
          phone_number:
            (payload.phoneNumber as string | undefined) ?? session.phone_number,
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

  function resetSession() {
    persistSession(null);
    setMessage(null);
  }

  return (
    <div className="surface-card rounded-[24px] p-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="eyebrow">Agent contact</p>
          <h2 className="mt-3 font-heading text-2xl font-semibold text-brand-ink">
            {displayName}
          </h2>
          <p className="section-copy mt-2 text-sm">
            {agentSummary?.location_label?.trim() || "Location not shared yet"}
          </p>
        </div>
        <StatusPill
          label={verified ? "Verified agent" : "Verification pending"}
          tone={verified ? "active" : "pending"}
        />
      </div>

      {unlockedPhone ? (
        <div className="soft-panel mt-5 p-5">
          <p className="eyebrow">Unlocked number</p>
          <p className="mt-3 text-2xl font-bold text-brand-navy">{unlockedPhone}</p>
          <div className="mt-4 flex flex-wrap gap-3">
            <a href={`tel:${unlockedPhone}`} className="btn btn-success">
              Call agent
            </a>
            <a
              href={`https://wa.me/${unlockedPhone.replace(/[^\d]/g, "")}`}
              target="_blank"
              rel="noreferrer"
              className="btn btn-outline"
            >
              WhatsApp
            </a>
          </div>
        </div>
      ) : session ? (
        <div className="soft-panel mt-5 p-5">
          <p className="text-lg font-semibold text-brand-ink">
            Amount: {session.amount ?? "-"} {session.currency ?? "TZS"}
          </p>
          <p className="section-copy mt-3 text-sm">
            {message ??
              "Payment request sent. Confirm it on your phone to unlock the agent number."}
          </p>
          {session.payment_method ? (
            <p className="mt-3 text-sm font-semibold text-brand-ink">
              Payment method: {session.payment_method}
            </p>
          ) : null}
          {session.customer_phone_number ? (
            <p className="field-help mt-2">
              Payment prompt sent to {session.customer_phone_number}.
            </p>
          ) : null}
          <div className="mt-5 flex flex-wrap gap-3">
            <button
              type="button"
              onClick={() => void checkPayment(false)}
              disabled={checking}
              className="btn btn-outline"
            >
              {checking ? "Checking..." : "Check payment now"}
            </button>
            <button type="button" onClick={resetSession} className="btn btn-ghost">
              Start a new payment
            </button>
          </div>
        </div>
      ) : (
        <div className="mt-5 grid gap-4">
          <p className="section-copy text-sm">
            Pay once through ClickPesa to reveal this agent phone number directly on
            this device.
          </p>
          <label className="grid gap-2">
            <span className="field-label">Full name</span>
            <input
              value={customerName}
              onChange={(event) => setCustomerName(event.target.value)}
              className="field-input"
              placeholder="Mfano: Amina Said"
            />
          </label>
          <label className="grid gap-2">
            <span className="field-label">Phone number</span>
            <input
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
            {submitting ? "Starting payment..." : "Pay and unlock number"}
          </button>
        </div>
      )}

      {message ? <p className="mt-4 text-sm text-muted">{message}</p> : null}
    </div>
  );
}
