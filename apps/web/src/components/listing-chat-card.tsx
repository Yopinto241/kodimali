"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useEffect, useState } from "react";
import { getBrowserSupabase } from "@/lib/supabase-browser";
import { useLanguage } from "@/components/language-provider";

type Row = Record<string, unknown>;

export function ListingChatCard({ listingId }: { listingId: string }) {
  const supabase = getBrowserSupabase();
  const { language } = useLanguage();
  const sw = language === "sw";
  const router = useRouter();
  const [signedIn, setSignedIn] = useState<boolean | null>(null);
  const [phone, setPhone] = useState("");
  const [paymentId, setPaymentId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [chatPrice, setChatPrice] = useState<number | null>(null);
  const [notice, setNotice] = useState("Chat directly with the listing agent.");

  useEffect(() => {
    void Promise.all([
      supabase.auth.getUser(),
      supabase.rpc("paid_chat_unlock_price"),
    ]).then(([auth, price]) => {
      const priceResult = price as unknown as {
        data: unknown;
        error: unknown;
      };
      setSignedIn(Boolean(auth.data.user));
      if (!priceResult.error && typeof priceResult.data === "number") {
        setChatPrice(priceResult.data);
      }
    });
  }, [supabase]);

  async function openConversation() {
    const { data, error } = await supabase.rpc(
      "get_or_create_listing_conversation",
      {
        p_listing_id: listingId,
      } as never,
    );
    if (error) throw error;
    const row = (Array.isArray(data) ? data[0] : data) as Row | null;
    if (!row?.id) throw new Error("The chat could not be opened.");
    router.push(`/account/chat/${String(row.id)}`);
  }

  async function start(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    try {
      const { data, error } = await supabase.functions.invoke(
        "create-listing-chat-payment",
        {
          body: { listing_id: listingId, phone_number: phone.trim() },
        },
      );
      if (error) throw error;
      const result = (data ?? {}) as Row;
      if (result.paymentRequired === false || result.paymentStatus === "paid") {
        await openConversation();
        return;
      }
      setPaymentId(String(result.paymentId));
      setNotice(
        "Payment request sent. Approve it on your phone, then check the status.",
      );
    } catch (error) {
      setNotice(readError(error));
    } finally {
      setBusy(false);
    }
  }

  async function check() {
    if (!paymentId) return;
    setBusy(true);
    try {
      const { data, error } = await supabase.functions.invoke(
        "check-listing-chat-payment",
        {
          body: { payment_id: paymentId },
        },
      );
      if (error) throw error;
      const result = (data ?? {}) as Row;
      if (result.paymentStatus === "paid") {
        await openConversation();
      } else {
        setNotice(
          `Payment status: ${String(result.paymentStatus ?? "pending")}.`,
        );
      }
    } catch (error) {
      setNotice(readError(error));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="surface-card p-6">
      <p className="eyebrow">{sw ? "Mazungumzo ya faragha" : "Private chat"}</p>
      <h2 className="mt-2 font-heading text-2xl font-semibold">
        {sw ? "Ongea na wakala" : "Chat with agent"}
      </h2>
      <p className="mt-2 text-sm text-muted">
        {sw
          ? "Chat inalinda namba yako. Ikiwa ada inatumika, kiasi kitaonyeshwa kabla hujaidhinisha malipo; ada hii si deposit ya rental."
          : "Chat keeps your phone number private. If a fee applies, the amount is shown before approval; it is not a rental deposit."}
      </p>
      <p className="mt-2 text-sm text-muted" role="status">
        {notice}
      </p>
      {chatPrice !== null ? (
        <p className="mt-2 text-sm font-semibold">
          {sw
            ? `Ada ya chat: TZS ${chatPrice.toLocaleString()}`
            : `Chat fee: TZS ${chatPrice.toLocaleString()}`}
        </p>
      ) : null}
      {signedIn === false ? (
        <Link
          className="btn btn-success mt-5"
          href={`/login?next=/listing/${listingId}`}
        >
          {sw ? "Ingia ili ku-chat" : "Sign in to chat"}
        </Link>
      ) : signedIn ? (
        paymentId ? (
          <button
            className="btn btn-success mt-5"
            type="button"
            disabled={busy}
            onClick={() => void check()}
          >
            {busy ? "Checking..." : "Check payment and open chat"}
          </button>
        ) : (
          <form className="mt-5 grid gap-3" onSubmit={start}>
            <label className="grid gap-2 text-sm font-semibold">
              Mobile-money number
              <input
                className="field-input"
                inputMode="tel"
                placeholder="2557XXXXXXXX"
                value={phone}
                onChange={(event) => setPhone(event.target.value)}
                required
              />
            </label>
            <button className="btn btn-success" disabled={busy}>
              {busy ? "Starting..." : "Continue to chat"}
            </button>
          </form>
        )
      ) : null}
    </section>
  );
}

function readError(error: unknown) {
  return error instanceof Error
    ? error.message
    : "The chat could not be opened.";
}
