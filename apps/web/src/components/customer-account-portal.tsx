"use client";

import Link from "next/link";
import { FormEvent, useCallback, useEffect, useState } from "react";
import type { User } from "@supabase/supabase-js";
import { getBrowserSupabase } from "@/lib/supabase-browser";

type BookingRow = {
  id: string;
  request_reference: string;
  booking_status: string;
  created_at: string;
  agent_id: string;
  listings: { title?: string; public_location_label?: string } | null;
  agents:
    | { display_name?: string; business_name?: string }
    | { display_name?: string; business_name?: string }[]
    | null;
};

export function CustomerAccountPortal() {
  const supabase = getBrowserSupabase();
  const [user, setUser] = useState<User | null>(null);
  const [mode, setMode] = useState<"login" | "register">("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [fullName, setFullName] = useState("");
  const [phone, setPhone] = useState("");
  const [claimReference, setClaimReference] = useState("");
  const [bookings, setBookings] = useState<BookingRow[]>([]);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const loadBookings = useCallback(async () => {
    const { data, error } = await supabase
      .from("booking_requests")
      .select(
        "id, request_reference, booking_status, created_at, agent_id, listings(title, public_location_label), agents(display_name, business_name)",
      )
      .order("created_at", { ascending: false });
    if (error) throw error;
    setBookings((data ?? []) as unknown as BookingRow[]);
  }, [supabase]);

  useEffect(() => {
    const applyUser = (nextUser: User | null) => {
      setUser(nextUser);
      if (nextUser) {
        void loadBookings().catch((error: unknown) =>
          setMessage(readError(error)),
        );
      } else {
        setBookings([]);
      }
    };
    void supabase.auth.getUser().then(({ data }) => applyUser(data.user));
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      applyUser(session?.user ?? null);
    });
    return () => data.subscription.unsubscribe();
  }, [loadBookings, supabase]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setMessage(null);
    try {
      if (mode === "register") {
        const { data, error } = await supabase.auth.signUp({
          email: email.trim(),
          password,
          options: {
            data: {
              full_name: fullName.trim(),
              phone_number: phone.trim(),
              preferred_language: "sw",
              registration_source: "customer_self_register",
            },
          },
        });
        if (error) throw error;
        setUser(data.user);
        setMessage(
          data.session
            ? "Account created. Your customer workspace is ready."
            : "Account created. Confirm the link sent to your email, then sign in.",
        );
      } else {
        const { data, error } = await supabase.auth.signInWithPassword({
          email: email.trim(),
          password,
        });
        if (error) throw error;
        setUser(data.user);
        setMessage("Signed in successfully.");
      }
    } catch (error) {
      setMessage(readError(error));
    } finally {
      setBusy(false);
    }
  }

  async function claimRequest(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setMessage(null);
    try {
      const { error } = await supabase.rpc("claim_my_booking_request", {
        p_request_reference: claimReference.trim(),
      } as never);
      if (error) throw error;
      setClaimReference("");
      await loadBookings();
      setMessage("Request connected to your account.");
    } catch (error) {
      setMessage(readError(error));
    } finally {
      setBusy(false);
    }
  }

  if (!user) {
    return (
      <section className="surface-card p-6 sm:p-8">
        <div className="flex flex-wrap gap-2" role="tablist" aria-label="Customer account">
          <button className={`btn ${mode === "login" ? "btn-success" : "btn-outline"}`} onClick={() => setMode("login")} type="button">Sign in</button>
          <button className={`btn ${mode === "register" ? "btn-success" : "btn-outline"}`} onClick={() => setMode("register")} type="button">Create customer account</button>
        </div>
        <form className="mt-6 grid max-w-xl gap-4" onSubmit={submit}>
          {mode === "register" ? <>
            <label className="grid gap-2 font-semibold">Full name<input className="rounded-2xl border border-brand-border bg-white px-4 py-3" value={fullName} onChange={(event) => setFullName(event.target.value)} required /></label>
            <label className="grid gap-2 font-semibold">Phone number<input className="rounded-2xl border border-brand-border bg-white px-4 py-3" value={phone} onChange={(event) => setPhone(event.target.value)} required /></label>
          </> : null}
          <label className="grid gap-2 font-semibold">Email<input className="rounded-2xl border border-brand-border bg-white px-4 py-3" type="email" value={email} onChange={(event) => setEmail(event.target.value)} required /></label>
          <label className="grid gap-2 font-semibold">Password<input className="rounded-2xl border border-brand-border bg-white px-4 py-3" type="password" minLength={6} value={password} onChange={(event) => setPassword(event.target.value)} required /></label>
          <button className="btn btn-success" disabled={busy}>{busy ? "Please wait..." : mode === "login" ? "Sign in" : "Create account"}</button>
        </form>
        {message ? <p className="mt-4 rounded-2xl bg-brand-info-soft p-4 text-sm text-brand-navy" role="status">{message}</p> : null}
      </section>
    );
  }

  return (
    <section className="surface-card p-6 sm:p-8">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div><p className="eyebrow">Signed in customer</p><p className="mt-2 font-semibold">{user.email}</p></div>
        <button className="btn btn-outline" type="button" onClick={() => void supabase.auth.signOut()}>Sign out</button>
      </div>
      <form className="soft-panel mt-6 flex flex-col gap-3 p-4 sm:flex-row" onSubmit={claimRequest}>
        <label className="grid flex-1 gap-2 font-semibold">Connect an earlier guest request<input className="rounded-2xl border border-brand-border bg-white px-4 py-3" placeholder="Request reference" value={claimReference} onChange={(event) => setClaimReference(event.target.value)} required /></label>
        <button className="btn btn-success self-end" disabled={busy}>Connect</button>
      </form>
      {message ? <p className="mt-4 rounded-2xl bg-brand-info-soft p-4 text-sm text-brand-navy" role="status">{message}</p> : null}
      <div className="mt-8">
        <h2 className="font-heading text-2xl font-semibold">My requests</h2>
        <div className="mt-4 grid gap-3">
          {bookings.length === 0 ? <p className="section-copy">No connected requests yet. Guest browsing and requests remain available.</p> : bookings.map((booking) => (
            <article className="soft-panel p-4" key={booking.id}>
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div><p className="font-semibold text-brand-ink">{booking.listings?.title ?? "Rental request"}</p><p className="mt-1 text-sm text-muted">{booking.request_reference} · {booking.listings?.public_location_label ?? ""}</p></div>
                <span className="rounded-full bg-brand-green-soft px-3 py-1 text-sm font-semibold text-brand-navy">{booking.booking_status.replaceAll("_", " ")}</span>
              </div>
              <p className="mt-3 text-sm text-muted">Assigned agent: {assignedAgentName(booking)}</p>
              <Link className="btn btn-outline mt-4" href={`/account/request/${booking.id}`}>Track and chat</Link>
            </article>
          ))}
        </div>
      </div>
      <p className="mt-6 text-sm text-muted">Need to remove your account? <Link className="font-semibold underline" href="/delete-account">Open account deletion</Link>.</p>
    </section>
  );
}

function readError(error: unknown) {
  return error instanceof Error ? error.message : "The request could not be completed.";
}

function assignedAgentName(booking: BookingRow) {
  const agent = Array.isArray(booking.agents) ? booking.agents[0] : booking.agents;
  return agent?.display_name ?? agent?.business_name ?? booking.agent_id;
}
