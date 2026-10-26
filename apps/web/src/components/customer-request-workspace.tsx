"use client";

import Link from "next/link";
import { FormEvent, useCallback, useEffect, useState } from "react";
import { getBrowserSupabase } from "@/lib/supabase-browser";

type DataRow = Record<string, unknown>;

export function CustomerRequestWorkspace({
  bookingRequestId,
}: {
  bookingRequestId: string;
}) {
  const supabase = getBrowserSupabase();
  const [booking, setBooking] = useState<DataRow | null>(null);
  const [conversationId, setConversationId] = useState<string | null>(null);
  const [messages, setMessages] = useState<DataRow[]>([]);
  const [paymentPhone, setPaymentPhone] = useState("");
  const [viewingStart, setViewingStart] = useState("");
  const [rating, setRating] = useState(5);
  const [reviewComment, setReviewComment] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("Loading request...");

  const load = useCallback(async () => {
    const { data: auth } = await supabase.auth.getUser();
    if (!auth.user) {
      setNotice("Sign in to open this request.");
      return;
    }
    const { data: request, error: requestError } = await supabase
      .from("booking_requests")
      .select(
        "id, request_reference, booking_status, booking_kind, owner_approval_status, accepted_at, payment_ready_at, completed_at, payment_expires_at, agent_id, requested_start_at, requested_end_at, created_at, booking_payment_transactions(status,amount_tzs,paid_at), listings(title, public_location_label), agents(display_name, business_name)",
      )
      .eq("id", bookingRequestId)
      .maybeSingle();
    if (requestError) throw requestError;
    if (!request) {
      setNotice(
        "This request is unavailable or is not connected to your account.",
      );
      return;
    }
    setBooking(request as DataRow);
    setNotice("");
    const { data: conversations, error: conversationError } =
      await supabase.rpc("get_or_create_booking_conversation", {
        p_booking_request_id: bookingRequestId,
      } as never);
    if (conversationError) throw conversationError;
    const rawConversations = conversations as unknown;
    const conversation = Array.isArray(rawConversations)
      ? (rawConversations[0] as DataRow | undefined)
      : (rawConversations as DataRow | null);
    const nextConversationId = conversation?.id as string | undefined;
    if (!nextConversationId) return;
    setConversationId(nextConversationId);
    const { data: initialMessages, error: messagesError } = await supabase
      .from("booking_messages")
      .select("id, sender_id, body, read_at, created_at")
      .eq("conversation_id", nextConversationId)
      .order("created_at");
    if (messagesError) throw messagesError;
    setMessages((initialMessages ?? []) as DataRow[]);
  }, [bookingRequestId, supabase]);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      void load().catch((error: unknown) => setNotice(readError(error)));
    }, 0);
    return () => window.clearTimeout(timer);
  }, [load]);

  useEffect(() => {
    if (!conversationId) return;
    const channel = supabase
      .channel(`web-booking-chat-${conversationId}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "booking_messages",
          filter: `conversation_id=eq.${conversationId}`,
        },
        (payload) => {
          const row = payload.new as DataRow;
          setMessages((current) =>
            current.some((item) => item.id === row.id)
              ? current
              : [...current, row],
          );
        },
      )
      .subscribe();
    return () => {
      void supabase.removeChannel(channel);
    };
  }, [conversationId, supabase]);

  async function sendResponse(responseCode: string) {
    if (!conversationId) return;
    setBusy(true);
    try {
      const { error } = await supabase.rpc("send_booking_response", {
        p_conversation_id: conversationId,
        p_response_code: responseCode,
        p_client_message_id: crypto.randomUUID(),
      } as never);
      if (error) throw error;
      setNotice("Jibu limetumwa kwa agent.");
    } catch (error) {
      setNotice(readError(error));
    } finally {
      setBusy(false);
    }
  }

  async function reserveAndPay() {
    setBusy(true);
    setNotice("Tunaandaa reservation yako...");
    try {
      const { data, error } = await supabase.functions.invoke(
        "create-platform-payment",
        {
          body: {
            purpose: "booking_reservation",
            resource_id: bookingRequestId,
            phone_number: paymentPhone,
          },
        },
      );
      if (error) throw error;
      if (data?.error) throw new Error(String(data.error));
      let status = String(data?.paymentStatus ?? "pending");
      if (status === "free") {
        setNotice("Reservation imethibitishwa bila malipo.");
        await load();
        return;
      }
      const paymentId = String(data?.paymentId ?? "");
      setNotice(
        `Thibitisha malipo ya TZS ${Number(data?.amount ?? 0).toLocaleString()} kwenye simu yako.`,
      );
      for (
        let attempt = 0;
        attempt < 30 &&
        !["paid", "failed", "cancelled", "expired"].includes(status);
        attempt++
      ) {
        await new Promise((resolve) => window.setTimeout(resolve, 3000));
        const checked = await supabase.functions.invoke(
          "check-platform-payment",
          { body: { payment_id: paymentId } },
        );
        if (checked.error) throw checked.error;
        status = String(checked.data?.paymentStatus ?? status);
      }
      if (status !== "paid") throw new Error(`Payment status: ${status}`);
      setNotice("Malipo yamethibitishwa. Reservation yako iko salama.");
      await load();
    } catch (error) {
      setNotice(readError(error));
    } finally {
      setBusy(false);
    }
  }

  async function proposeViewing(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const start = new Date(viewingStart);
    const end = new Date(start.getTime() + 60 * 60 * 1000);
    setBusy(true);
    try {
      const { error } = await supabase.rpc("propose_viewing_appointment", {
        p_booking_request_id: bookingRequestId,
        p_scheduled_start_at: start.toISOString(),
        p_scheduled_end_at: end.toISOString(),
        p_location_note: null,
      } as never);
      if (error) throw error;
      setViewingStart("");
      setNotice("Viewing time proposed. The assigned agent has been notified.");
    } catch (error) {
      setNotice(readError(error));
    } finally {
      setBusy(false);
    }
  }

  async function submitReview(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    try {
      const { error } = await supabase.rpc("submit_verified_review", {
        p_booking_request_id: bookingRequestId,
        p_rating: rating,
        p_comment: reviewComment.trim() || null,
      } as never);
      if (error) throw error;
      setNotice("Thank you. Your verified review was submitted.");
    } catch (error) {
      setNotice(readError(error));
    } finally {
      setBusy(false);
    }
  }

  if (!booking) {
    return (
      <section className="surface-card p-6 sm:p-8">
        <p className="section-copy">{notice}</p>
        <Link className="btn btn-outline mt-5" href="/account">
          Back to account
        </Link>
      </section>
    );
  }

  const listing = relation(booking.listings);
  const agent = relation(booking.agents);
  const completed = booking.booking_status === "completed";
  const payments = Array.isArray(booking.booking_payment_transactions)
    ? booking.booking_payment_transactions
    : [];
  const paid = payments.some((item) => relation(item)?.status === "paid");
  const ownerReady = ["approved", "not_required"].includes(
    String(booking.owner_approval_status ?? "not_required"),
  );
  const canReserve =
    Boolean(booking.accepted_at) && ownerReady && !paid && !completed;
  return (
    <div className="grid gap-6 lg:grid-cols-[0.8fr_1.2fr]">
      <div className="space-y-6">
        <section className="surface-card p-6">
          <p className="eyebrow">Request {String(booking.request_reference)}</p>
          <h1 className="mt-3 font-heading text-3xl font-semibold">
            {String(listing?.title ?? "Rental request")}
          </h1>
          <p className="section-copy mt-2">
            {String(listing?.public_location_label ?? "")}
          </p>
          <div className="soft-panel mt-5 p-4">
            <p className="text-sm text-muted">Assigned agent</p>
            <p className="mt-1 font-semibold">
              {String(
                agent?.display_name ?? agent?.business_name ?? booking.agent_id,
              )}
            </p>
            <p className="mt-2 text-sm text-muted">
              Status: {String(booking.booking_status).replaceAll("_", " ")}
            </p>
          </div>
          <div className="mt-5 grid gap-2 text-sm">
            <Progress done label="Booking imetumwa" />
            <Progress
              done={Boolean(booking.accepted_at)}
              label="Agent amekubali na anakagua upatikanaji"
            />
            <Progress done={ownerReady} label="Owner/manager approval" />
            <Progress
              done={paid || booking.booking_status === "confirmed"}
              label="Reservation na malipo yamethibitishwa"
            />
            <Progress done={completed} label="Huduma imekamilika" />
          </div>
        </section>
        {canReserve ? (
          <section className="surface-card p-6">
            <p className="eyebrow">Hatua yako sasa</p>
            <h2 className="mt-2 font-heading text-2xl font-semibold">
              Reserve na ulipe
            </h2>
            <p className="mt-2 text-sm text-muted">
              Malipo yakithibitishwa, muda uliochagua unahifadhiwa kwenye
              inventory na booking inakuwa confirmed.
            </p>
            <label className="mt-4 grid gap-2 font-semibold">
              Namba ya malipo
              <input
                className="field-input"
                type="tel"
                inputMode="tel"
                placeholder="2557XXXXXXXX"
                value={paymentPhone}
                onChange={(event) => setPaymentPhone(event.target.value)}
              />
            </label>
            <button
              className="btn btn-success mt-4 w-full"
              disabled={busy}
              onClick={() => void reserveAndPay()}
            >
              Reserve / Pay
            </button>
          </section>
        ) : null}
        <form className="surface-card p-6" onSubmit={proposeViewing}>
          <h2 className="font-heading text-xl font-semibold">
            Propose a viewing
          </h2>
          <label className="mt-4 grid gap-2 font-semibold">
            Date and time
            <input
              className="rounded-2xl border border-brand-border bg-white px-4 py-3"
              type="datetime-local"
              value={viewingStart}
              onChange={(event) => setViewingStart(event.target.value)}
              required
            />
          </label>
          <button className="btn btn-success mt-4" disabled={busy}>
            Send to assigned agent
          </button>
        </form>
        {completed ? (
          <form className="surface-card p-6" onSubmit={submitReview}>
            <h2 className="font-heading text-xl font-semibold">
              Verified rental review
            </h2>
            <label className="mt-4 grid gap-2 font-semibold">
              Rating
              <select
                className="rounded-2xl border border-brand-border bg-white px-4 py-3"
                value={rating}
                onChange={(event) => setRating(Number(event.target.value))}
              >
                {[5, 4, 3, 2, 1].map((value) => (
                  <option key={value} value={value}>
                    {value} / 5
                  </option>
                ))}
              </select>
            </label>
            <label className="mt-4 grid gap-2 font-semibold">
              Comment
              <textarea
                className="min-h-24 rounded-2xl border border-brand-border bg-white px-4 py-3"
                value={reviewComment}
                onChange={(event) => setReviewComment(event.target.value)}
              />
            </label>
            <button className="btn btn-success mt-4" disabled={busy}>
              Submit review
            </button>
          </form>
        ) : null}
      </div>
      <section className="surface-card flex min-h-[560px] flex-col p-6">
        <h2 className="font-heading text-2xl font-semibold">
          Booking follow-up
        </h2>
        <p className="mt-2 text-sm text-muted">
          Tumia majibu haya mafupi kuthibitisha hatua. Chat ya kawaida inabaki
          kwenye paid chat ya listing.
        </p>
        <div
          className="my-5 flex-1 space-y-3 overflow-y-auto rounded-2xl bg-brand-card-soft p-4"
          aria-live="polite"
        >
          {messages.length === 0 ? (
            <p className="text-sm text-muted">
              No messages yet. Ask the assigned agent about availability or a
              viewing.
            </p>
          ) : (
            messages.map((message) => (
              <article
                className="rounded-2xl bg-white p-3 shadow-sm"
                key={String(message.id)}
              >
                <p>{String(message.body ?? "")}</p>
                <p className="mt-1 text-xs text-muted">
                  {new Date(String(message.created_at)).toLocaleString()}
                </p>
              </article>
            ))
          )}
        </div>
        <div className="flex flex-wrap gap-2">
          <button
            className="btn btn-outline"
            disabled={busy || !conversationId}
            onClick={() => void sendResponse("acknowledged")}
          >
            Nimepokea
          </button>
          <button
            className="btn btn-outline"
            disabled={busy || !conversationId}
            onClick={() => void sendResponse("still_interested")}
          >
            Bado ninahitaji
          </button>
          <button
            className="btn btn-outline"
            disabled={busy || !conversationId}
            onClick={() => void sendResponse("confirm_viewing")}
          >
            Thibitisha viewing
          </button>
          <button
            className="btn btn-outline"
            disabled={busy || !conversationId}
            onClick={() => void sendResponse("request_reschedule")}
          >
            Badilisha muda
          </button>
          <button
            className="btn btn-outline"
            disabled={busy || !conversationId}
            onClick={() => void sendResponse("not_interested")}
          >
            Sihitaji tena
          </button>
        </div>
        {notice ? (
          <p className="mt-3 text-sm text-brand-navy" role="status">
            {notice}
          </p>
        ) : null}
      </section>
    </div>
  );
}

function relation(value: unknown): DataRow | null {
  if (Array.isArray(value)) return (value[0] as DataRow | undefined) ?? null;
  return value && typeof value === "object" ? (value as DataRow) : null;
}

function readError(error: unknown) {
  if (error instanceof Error) return error.message;
  if (error && typeof error === "object" && "message" in error) {
    return String(
      (error as { message?: unknown }).message ??
        "The request could not be completed.",
    );
  }
  return "The request could not be completed.";
}

function Progress({ done, label }: { done: boolean; label: string }) {
  return (
    <div
      className={`rounded-xl px-3 py-2 font-semibold ${done ? "bg-brand-green-soft text-brand-navy" : "bg-brand-card-soft text-muted"}`}
    >
      {done ? "✓" : "○"} {label}
    </div>
  );
}
