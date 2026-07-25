"use client";

import Link from "next/link";
import { FormEvent, useEffect, useState } from "react";
import type { User } from "@supabase/supabase-js";
import { getBrowserSupabase } from "@/lib/supabase-browser";

export function AccountDeletionForm() {
  const supabase = getBrowserSupabase();
  const [user, setUser] = useState<User | null>(null);
  const [reason, setReason] = useState("");
  const [checking, setChecking] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    void supabase.auth.getUser().then(({ data }) => {
      setUser(data.user);
      setChecking(false);
    });
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
      setChecking(false);
    });
    return () => data.subscription.unsubscribe();
  }, [supabase]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!window.confirm("Send an account deletion request to KODIMALI?")) return;
    setSubmitting(true);
    setMessage(null);
    const { error } = await supabase.rpc("request_my_account_deletion", {
      p_reason: reason.trim() || null,
    } as never);
    setSubmitting(false);
    setMessage(
      error
        ? error.message
        : "Your deletion request was submitted. Support will verify ownership and process it.",
    );
  }

  if (checking) {
    return <p className="section-copy" role="status">Checking your account…</p>;
  }

  if (!user) {
    return (
      <p className="section-copy">
        <Link className="font-semibold underline" href="/account">Sign in to your customer account</Link>{" "}
        to submit a verified in-app deletion request. The support option below remains available for every account type.
      </p>
    );
  }

  return (
    <form className="grid max-w-2xl gap-4" onSubmit={submit}>
      <p className="section-copy">Signed in as <strong>{user.email}</strong>.</p>
      <label className="grid gap-2 font-semibold">
        Reason (optional)
        <textarea
          className="min-h-28 rounded-2xl border border-brand-border bg-white px-4 py-3"
          maxLength={1000}
          onChange={(event) => setReason(event.target.value)}
          value={reason}
        />
      </label>
      <button className="btn btn-outline justify-self-start" disabled={submitting}>
        {submitting ? "Sending…" : "Request account deletion"}
      </button>
      {message ? <p className="rounded-2xl bg-brand-info-soft p-4 text-sm text-brand-navy" role="status">{message}</p> : null}
    </form>
  );
}
