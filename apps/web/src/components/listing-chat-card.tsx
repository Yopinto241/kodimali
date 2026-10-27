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
    <section className="overflow-hidden rounded-[22px] border border-[#075e54]/20 bg-[#f7faf8] shadow-[0_18px_45px_rgba(7,94,84,.12)]">
      <div className="flex items-center gap-3 bg-gradient-to-r from-[#075e54] to-[#087f6d] px-5 py-4 text-white">
        <span className="grid size-11 place-items-center rounded-full bg-[#d9fdd3] text-[#075e54]">
          <svg className="size-6 fill-none stroke-current stroke-2" viewBox="0 0 24 24" aria-hidden="true"><path d="M7 18.5 3.5 21l1-4A8 8 0 1 1 7 18.5Z" /><path d="M8 10h8M8 14h5" /></svg>
        </span>
        <div>
          <p className="text-xs font-bold uppercase tracking-[.13em] text-white/70">{sw ? "Mazungumzo ya faragha" : "Private chat"}</p>
          <h2 className="mt-0.5 text-xl font-bold">{sw ? "Zungumza na wakala" : "Chat with the agent"}</h2>
        </div>
      </div>
      <div className="p-5 sm:p-6">
      <p className="text-sm leading-6 text-[#3b4a54]">
        {sw
          ? "Namba yako hubaki siri. Lipa mara moja, kisha zungumza na wakala kwa siku 7."
          : "Your number stays private. Pay once, then chat with the agent for 7 days."}
      </p>
      <p className="mt-3 rounded-xl bg-[#e7f7f1] px-3 py-2 text-sm text-[#075e54]" role="status">
        {notice}
      </p>
      {chatPrice !== null ? (
        <p className="mt-3 text-lg font-extrabold text-[#075e54]">
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
            <button className="btn border-0 bg-[#00a884] text-white hover:bg-[#008f72]" disabled={busy}>
              {busy ? "Starting..." : "Continue to chat"}
            </button>
          </form>
        )
      ) : null}
      </div>
    </section>
  );
}

function readError(error: unknown) {
  return error instanceof Error
    ? error.message
    : "The chat could not be opened.";
}
