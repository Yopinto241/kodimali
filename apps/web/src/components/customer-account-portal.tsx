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
  requested_start_at?: string | null;
  requested_end_at?: string | null;
  owner_approval_status?: string;
  accepted_at?: string | null;
  payment_ready_at?: string | null;
  completed_at?: string | null;
  booking_kind?: string;
  booking_payment_transactions?: Array<{
    status?: string;
    amount_tzs?: number;
  }>;
  listings: { title?: string; public_location_label?: string } | null;
  agents:
    | { display_name?: string; business_name?: string }
    | { display_name?: string; business_name?: string }[]
    | null;
};

type CustomerAccountPortalProps = {
  initialMode?: "login" | "register";
  destination?: string;
  accountKind?: "customer" | "owner";
};

export function CustomerAccountPortal({
  initialMode = "login",
  destination,
  accountKind = "customer",
}: CustomerAccountPortalProps) {
  const supabase = getBrowserSupabase();
  const [user, setUser] = useState<User | null>(null);
  const [mode, setMode] = useState<"login" | "register">(initialMode);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [fullName, setFullName] = useState("");
  const [phone, setPhone] = useState("");
  const [paymentPhone, setPaymentPhone] = useState("");
  const [claimReference, setClaimReference] = useState("");
  const [bookings, setBookings] = useState<BookingRow[]>([]);
  const [tenantToken, setTenantToken] = useState("");
  const [rentalAgreements, setRentalAgreements] = useState<
    Array<Record<string, unknown>>
  >([]);
  const [eventPlans, setEventPlans] = useState<Array<Record<string, unknown>>>(
    [],
  );
  const [individualEventBookings, setIndividualEventBookings] = useState<
    Array<Record<string, unknown>>
  >([]);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const loadBookings = useCallback(async () => {
    const { data, error } = await supabase
      .from("booking_requests")
      .select(
        "id, request_reference, booking_status, booking_kind, requested_start_at, requested_end_at, owner_approval_status, accepted_at, payment_ready_at, completed_at, created_at, agent_id, booking_payment_transactions(status,amount_tzs), listings(title, public_location_label), agents(display_name, business_name)",
      )
      .order("created_at", { ascending: false });
    if (error) throw error;
    setBookings((data ?? []) as unknown as BookingRow[]);
  }, [supabase]);

  const loadRentalAgreements = useCallback(async () => {
    const { data, error } = await supabase
      .from("rental_agreements")
      .select("*, rental_assets(display_name)")
      .order("created_at", { ascending: false });
    if (error) throw error;
    setRentalAgreements(
      (data ?? []) as unknown as Array<Record<string, unknown>>,
    );
  }, [supabase]);

  const loadEventPlans = useCallback(async () => {
    const { data, error } = await supabase
      .from("event_plans")
      .select(
        "id,reference,title,event_period,attendance,budget_tzs,status,created_at,event_types(name_sw,name_en),event_quote_revisions(id,revision,total_tzs,status,expires_at),event_agreements(id,version,terms,status,sent_at)",
      )
      .order("created_at", { ascending: false });
    if (error) {
      if (error.code === "42P01" || error.code === "PGRST205") return;
      throw error;
    }
    setEventPlans((data ?? []) as unknown as Array<Record<string, unknown>>);
  }, [supabase]);

  const loadIndividualEventBookings = useCallback(async () => {
    const { data, error } = await supabase
      .from("event_individual_bookings")
      .select(
        "id,reference,booking_kind,requested_period,requested_quantity,quoted_amount_tzs,status,payment_status,customer_message,provider_response,created_at,event_plan_items(item_kind,event_equipment_items(name),event_service_offerings(title,event_service_profiles(display_name)))",
      )
      .order("created_at", { ascending: false });
    if (error) {
      if (error.code === "42P01" || error.code === "PGRST205") return;
      throw error;
    }
    setIndividualEventBookings(
      (data ?? []) as unknown as Array<Record<string, unknown>>,
    );
  }, [supabase]);

  useEffect(() => {
    const applyUser = (nextUser: User | null) => {
      setUser(nextUser);
      if (nextUser) {
        void loadBookings().catch((error: unknown) =>
          setMessage(readError(error)),
        );
        void loadRentalAgreements().catch((error: unknown) =>
          setMessage(readError(error)),
        );
        void loadEventPlans().catch((error: unknown) =>
          setMessage(readError(error)),
        );
        void loadIndividualEventBookings().catch((error: unknown) =>
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
  }, [
    loadBookings,
    loadEventPlans,
    loadIndividualEventBookings,
    loadRentalAgreements,
    supabase,
  ]);

  async function acceptTenantInvitation(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setMessage(null);
    const { error } = await supabase.rpc("accept_tenant_invitation", {
      p_token: tenantToken.trim(),
    } as never);
    setBusy(false);
    if (error) setMessage(error.message);
    else {
      setTenantToken("");
      setMessage(
        "Invitation accepted. The owner can now prepare your rental agreement.",
      );
      await loadRentalAgreements();
    }
  }
  async function acceptRentalAgreement(id: string) {
    setBusy(true);
    setMessage(null);
    const { error } = await supabase.rpc("accept_rental_agreement", {
      p_agreement_id: id,
    } as never);
    setBusy(false);
    setMessage(error?.message ?? "Rental agreement accepted and activated.");
    if (!error) await loadRentalAgreements();
  }
  async function acceptEventQuote(id: string) {
    setBusy(true);
    setMessage(null);
    const { error } = await supabase.rpc("accept_event_quote", {
      p_quote_revision_id: id,
    } as never);
    setBusy(false);
    setMessage(
      error?.message ??
        "Quotation accepted. Your final event agreement is being prepared.",
    );
    if (!error) await loadEventPlans();
  }
  async function acceptEventAgreement(id: string) {
    setBusy(true);
    setMessage(null);
    const { error } = await supabase.rpc("accept_event_agreement", {
      p_agreement_id: id,
    } as never);
    setBusy(false);
    setMessage(
      error?.message ??
        "Makubaliano yamekubaliwa. Lipa deposit ili kuthibitisha tukio.",
    );
    if (!error) await loadEventPlans();
  }

  async function pay(
    purpose: "booking_reservation" | "event_deposit" | "event_balance",
    resourceId: string,
  ) {
    setBusy(true);
    setMessage("Ombi la malipo linatumwa kwenye simu yako...");
    try {
      const started = await supabase.functions.invoke(
        "create-platform-payment",
        {
          body: {
            purpose,
            resource_id: resourceId,
            phone_number: paymentPhone,
          },
        },
      );
      if (started.error) throw started.error;
      if (started.data?.error) throw new Error(String(started.data.error));
      let status = String(started.data?.paymentStatus ?? "pending");
      if (status === "free") {
        setMessage(
          "Booking imethibitishwa bila malipo kwa sababu admin amewasha free booking.",
        );
        await loadBookings();
        return;
      }
      const paymentId = String(started.data?.paymentId ?? "");
      setMessage(
        `Thibitisha TZS ${Number(started.data?.amount ?? 0).toLocaleString()} kwenye simu yako.`,
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
        if (checked.data?.error) throw new Error(String(checked.data.error));
        status = String(checked.data?.paymentStatus ?? status);
      }
      if (status !== "paid")
        throw new Error(
          status === "failed"
            ? "Malipo hayakukamilika. Jaribu tena."
            : "Malipo bado hayajathibitishwa. Unaweza kuangalia tena kwenye akaunti yako.",
        );
      setMessage("Malipo yamethibitishwa na booking imehifadhiwa.");
      await Promise.all([
        loadBookings(),
        loadEventPlans(),
        loadIndividualEventBookings(),
      ]);
    } catch (error) {
      setMessage(readError(error));
    } finally {
      setBusy(false);
    }
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setMessage(null);
    try {
      const requestedNext =
        destination ?? new URLSearchParams(window.location.search).get("next");
      const nextPath =
        requestedNext?.startsWith("/") && !requestedNext.startsWith("//")
          ? requestedNext
          : "/account";
      if (mode === "register") {
        const { data, error } = await supabase.auth.signUp({
          email: email.trim(),
          password,
          options: {
            emailRedirectTo: `${window.location.origin}${nextPath}`,
            data: {
              full_name: fullName.trim(),
              phone_number: phone.trim(),
              preferred_language: "sw",
              registration_source:
                accountKind === "owner"
                  ? "owner_self_register"
                  : "customer_self_register",
              register_as_owner: accountKind === "owner",
              owner_type:
                accountKind === "owner"
                  ? (new URLSearchParams(nextPath.split("?")[1] ?? "").get(
                      "type",
                    ) ?? "individual")
                  : undefined,
              authorization_summary:
                accountKind === "owner"
                  ? "Ownership or management authority must be verified before workspace access."
                  : undefined,
            },
          },
        });
        if (error) throw error;
        setUser(data.user);
        setMessage(
          data.session
            ? accountKind === "owner"
              ? "Account created. Continue with owner verification."
              : "Account created. Your customer workspace is ready."
            : "Account created. Confirm the link sent to your email, then sign in.",
        );
        if (data.session && nextPath !== "/account")
          window.location.assign(nextPath);
      } else {
        const { data, error } = await supabase.auth.signInWithPassword({
          email: email.trim(),
          password,
        });
        if (error) throw error;
        setUser(data.user);
        setMessage("Signed in successfully.");
        if (nextPath !== "/account") window.location.assign(nextPath);
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
        {accountKind === "owner" ? (
          <div className="mb-6 max-w-xl">
            <h2 className="font-heading text-2xl font-semibold">
              Create your secure login
            </h2>
            <p className="mt-2 text-sm text-muted">
              After your email is confirmed, you will provide your owner type,
              legal name, phone number, and explain your ownership or management
              authority for administrator review.
            </p>
          </div>
        ) : null}
        <div
          className="flex flex-wrap gap-2"
          role="tablist"
          aria-label="Customer account"
        >
          <button
            className={`btn ${mode === "login" ? "btn-success" : "btn-outline"}`}
            onClick={() => setMode("login")}
            type="button"
          >
            Ingia
          </button>
          <button
            className={`btn ${mode === "register" ? "btn-success" : "btn-outline"}`}
            onClick={() => setMode("register")}
            type="button"
          >
            Jisajili
          </button>
        </div>
        <form className="mt-6 grid max-w-xl gap-4" onSubmit={submit}>
          {mode === "register" ? (
            <>
              <label className="grid gap-2 font-semibold">
                Jina kamili
                <input
                  className="rounded-2xl border border-brand-border bg-white px-4 py-3"
                  autoComplete="name"
                  value={fullName}
                  onChange={(event) => setFullName(event.target.value)}
                  required
                />
              </label>
              <label className="grid gap-2 font-semibold">
                Namba ya simu
                <input
                  className="rounded-2xl border border-brand-border bg-white px-4 py-3"
                  type="tel"
                  autoComplete="tel"
                  value={phone}
                  onChange={(event) => setPhone(event.target.value)}
                  required
                />
              </label>
            </>
          ) : null}
          <label className="grid gap-2 font-semibold">
            Barua pepe
            <input
              className="rounded-2xl border border-brand-border bg-white px-4 py-3"
              type="email"
              autoComplete="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              required
            />
          </label>
          <label className="grid gap-2 font-semibold">
            Nenosiri
            <input
              className="rounded-2xl border border-brand-border bg-white px-4 py-3"
              type="password"
              autoComplete={
                mode === "login" ? "current-password" : "new-password"
              }
              minLength={6}
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              required
            />
          </label>
          <button className="btn btn-success" disabled={busy}>
            {busy ? "Subiri..." : mode === "login" ? "Ingia" : "Fungua akaunti"}
          </button>
          <p className="text-sm text-muted">
            {mode === "login" ? "Huna akaunti?" : "Tayari una akaunti?"}{" "}
            <button
              className="font-semibold text-brand-navy underline"
              type="button"
              onClick={() => setMode(mode === "login" ? "register" : "login")}
            >
              {mode === "login" ? "Jisajili hapa" : "Ingia hapa"}
            </button>
          </p>
        </form>
        {message ? (
          <p
            className="mt-4 rounded-2xl bg-brand-info-soft p-4 text-sm text-brand-navy"
            role="status"
          >
            {message}
          </p>
        ) : null}
      </section>
    );
  }

  return (
    <section className="surface-card p-6 sm:p-8">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="font-heading text-3xl font-semibold">Akaunti Yangu</h1>
          <p className="mt-1 text-sm text-muted">{user.email}</p>
        </div>
        <button
          className="btn btn-outline"
          type="button"
          onClick={() => void supabase.auth.signOut()}
        >
          Toka
        </button>
      </div>
      <div className="mt-6 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <AccountAction href="/toa-taarifa" title="Toa Taarifa" />
        <AccountAction
          href="/toa-taarifa#taarifa-zangu"
          title="Taarifa Zangu"
        />
        <AccountAction href="/listings" title="Tafuta Mali" />
        <AccountAction href="/account#shughuli" title="Shughuli Zangu" />
        <AccountAction href="/events" title="Panga Sherehe" />
      </div>
      <form
        className="soft-panel mt-6 flex flex-col gap-3 p-4 sm:flex-row"
        onSubmit={claimRequest}
      >
        <label className="grid flex-1 gap-2 font-semibold">
          Connect an earlier guest request
          <input
            className="rounded-2xl border border-brand-border bg-white px-4 py-3"
            placeholder="Request reference"
            value={claimReference}
            onChange={(event) => setClaimReference(event.target.value)}
            required
          />
        </label>
        <button className="btn btn-success self-end" disabled={busy}>
          Connect
        </button>
      </form>
      {message ? (
        <p
          className="mt-4 rounded-2xl bg-brand-info-soft p-4 text-sm text-brand-navy"
          role="status"
        >
          {message}
        </p>
      ) : null}
      <label className="mt-6 grid max-w-md gap-2 font-semibold">
        Namba ya simu ya malipo
        <input
          className="field-input"
          type="tel"
          inputMode="tel"
          placeholder="2557XXXXXXXX"
          value={paymentPhone}
          onChange={(event) => setPaymentPhone(event.target.value)}
        />
        <span className="text-xs font-normal text-muted">
          SonicPesa itatuma ombi la kuthibitisha malipo kwenye namba hii.
        </span>
      </label>
      <div className="mt-8">
        <h2 className="font-heading text-2xl font-semibold">
          Miadi na Booking Zangu
        </h2>
        <div className="mt-4 grid gap-3">
          {bookings.length === 0 ? (
            <p className="text-muted">Hakuna booking.</p>
          ) : (
            bookings.map((booking) => (
              <article className="soft-panel p-4" key={booking.id}>
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <p className="font-semibold text-brand-ink">
                      {booking.listings?.title ?? "Rental request"}
                    </p>
                    <p className="mt-1 text-sm text-muted">
                      {booking.request_reference} ·{" "}
                      {booking.listings?.public_location_label ?? ""}
                    </p>
                  </div>
                  <span className="rounded-full bg-brand-green-soft px-3 py-1 text-sm font-semibold text-brand-navy">
                    {booking.booking_status.replaceAll("_", " ")}
                  </span>
                </div>
                <p className="mt-3 text-sm text-muted">
                  Assigned agent: {assignedAgentName(booking)}
                </p>
                <p className="mt-2 rounded-xl bg-brand-green-soft px-3 py-2 text-sm font-semibold text-brand-navy">
                  {booking.booking_status === "completed"
                    ? "Imekamilika: huduma au upangishaji umethibitishwa kuwa umefanyika."
                    : booking.booking_payment_transactions?.[0]?.status ===
                        "paid"
                      ? "Malipo yamethibitishwa. Booking yako imehifadhiwa."
                      : booking.owner_approval_status === "pending"
                        ? "Inasubiri mmiliki au msimamizi kuthibitisha."
                        : booking.payment_ready_at
                          ? "Imekubaliwa. Lipa sasa ili kuhifadhi booking yako."
                          : booking.accepted_at
                            ? "Imekubaliwa; upatikanaji na hatua ya malipo vinaandaliwa."
                            : "Imetumwa. Inasubiri agent aikubali na kuthibitisha upatikanaji."}
                </p>
                <div className="mt-4 flex flex-wrap gap-2">
                  <Link
                    className="btn btn-outline"
                    href={`/account/request/${booking.id}`}
                  >
                    Track and chat
                  </Link>
                  {booking.requested_start_at &&
                  booking.requested_end_at &&
                  booking.booking_payment_transactions?.[0]?.status !==
                    "paid" &&
                  (booking.owner_approval_status === "approved" ||
                    booking.owner_approval_status === "not_required") ? (
                    <button
                      className="btn btn-success"
                      disabled={busy}
                      onClick={() =>
                        void pay("booking_reservation", booking.id)
                      }
                    >
                      Lipa na uhifadhi
                    </button>
                  ) : null}
                </div>
              </article>
            ))
          )}
        </div>
      </div>
      <section className="mt-8">
        <h2 className="font-heading text-2xl font-semibold">
          Rental connection
        </h2>
        <form
          className="soft-panel mt-4 flex flex-col gap-3 p-4 sm:flex-row"
          onSubmit={acceptTenantInvitation}
        >
          <label className="grid flex-1 gap-2 font-semibold">
            Private invitation token
            <input
              className="field-input"
              value={tenantToken}
              onChange={(event) => setTenantToken(event.target.value)}
              required
            />
          </label>
          <button className="btn btn-success self-end" disabled={busy}>
            Accept owner invitation
          </button>
        </form>
        <div className="mt-4 grid gap-3">
          {rentalAgreements.length === 0 ? (
            <p className="text-muted">No rental agreements found.</p>
          ) : (
            rentalAgreements.map((agreement) => (
              <article className="soft-panel p-4" key={String(agreement.id)}>
                <p className="font-semibold">
                  {String(
                    (agreement.rental_assets as Record<string, unknown> | null)
                      ?.display_name ?? "Rental agreement",
                  )}
                </p>
                <p className="mt-1 text-sm text-muted">
                  {String(agreement.starts_on)} · TZS{" "}
                  {Number(agreement.rent_amount_tzs ?? 0).toLocaleString()} /{" "}
                  {String(agreement.rent_period)}
                </p>
                <p className="mt-2 text-sm font-semibold">
                  {String(agreement.status).replaceAll("_", " ")}
                </p>
                {agreement.status === "pending_tenant" ? (
                  <button
                    className="btn btn-success mt-3"
                    disabled={busy}
                    onClick={() =>
                      void acceptRentalAgreement(String(agreement.id))
                    }
                  >
                    Accept agreement
                  </button>
                ) : null}
              </article>
            ))
          )}
        </div>
      </section>
      <section className="mt-8" id="event-plans">
        <div className="flex flex-wrap items-end justify-between gap-3">
          <div>
            <h2 className="font-heading text-2xl font-semibold">
              Booking za kifaa na huduma
            </h2>
            <p className="mt-1 text-sm text-muted">
              Maombi ya kifaa kimoja au mtaalamu mmoja.
            </p>
          </div>
          <Link
            href="/events#individual-marketplace"
            className="btn btn-outline"
          >
            Tafuta huduma
          </Link>
        </div>
        <div className="mt-4 grid gap-3">
          {individualEventBookings.length === 0 ? (
            <p className="text-muted">Bado huna booking ya Events.</p>
          ) : (
            individualEventBookings.map((booking) => {
              const item = booking.event_plan_items as Record<
                string,
                unknown
              > | null;
              const equipment = item?.event_equipment_items as Record<
                string,
                unknown
              > | null;
              const offering = item?.event_service_offerings as Record<
                string,
                unknown
              > | null;
              const professional = offering?.event_service_profiles as Record<
                string,
                unknown
              > | null;
              const period = String(booking.requested_period ?? "")
                .replace(/[\[\)"]/g, "")
                .split(",");
              return (
                <article className="soft-panel p-4" key={String(booking.id)}>
                  <div className="flex flex-wrap justify-between gap-3">
                    <div>
                      <p className="font-semibold">
                        {String(
                          equipment?.name ?? offering?.title ?? "Event booking",
                        )}
                      </p>
                      <p className="mt-1 text-sm text-muted">
                        {String(booking.reference)}
                        {professional?.display_name
                          ? ` · ${String(professional.display_name)}`
                          : ""}
                      </p>
                    </div>
                    <span className="rounded-full bg-brand-green-soft px-3 py-1 text-sm font-semibold">
                      {String(booking.status).replaceAll("_", " ")}
                    </span>
                  </div>
                  <p className="mt-3 text-sm text-muted">
                    {period[0] ? new Date(period[0]).toLocaleString() : ""}
                    {period[1]
                      ? ` — ${new Date(period[1]).toLocaleString()}`
                      : ""}
                    {booking.requested_quantity
                      ? ` · Idadi ${String(booking.requested_quantity)}`
                      : ""}
                  </p>
                  {booking.quoted_amount_tzs != null ? (
                    <p className="mt-2 font-semibold">
                      TZS {Number(booking.quoted_amount_tzs).toLocaleString()}
                    </p>
                  ) : null}
                  <p className="mt-2 text-sm">
                    Malipo:{" "}
                    {String(booking.payment_status).replaceAll("_", " ")}
                  </p>
                  {booking.provider_response ? (
                    <p className="mt-2 text-sm text-muted">
                      {String(booking.provider_response)}
                    </p>
                  ) : null}
                </article>
              );
            })
          )}
        </div>
      </section>
      <section className="mt-8">
        <div className="flex flex-wrap items-end justify-between gap-3">
          <div>
            <h2 className="font-heading text-2xl font-semibold">
              Sherehe na Matukio
            </h2>
            <p className="mt-1 text-sm text-muted">
              Mipango, provider confirmations na quotations zako.
            </p>
          </div>
          <Link href="/events#plan-event" className="btn btn-outline">
            Panga tukio
          </Link>
        </div>
        <div className="mt-4 grid gap-3">
          {eventPlans.length === 0 ? (
            <p className="text-muted">Bado huna mpango wa tukio.</p>
          ) : (
            eventPlans.map((plan) => {
              const quotes =
                (plan.event_quote_revisions as Array<
                  Record<string, unknown>
                > | null) ?? [];
              const agreements =
                (plan.event_agreements as Array<
                  Record<string, unknown>
                > | null) ?? [];
              const sent = quotes.find((quote) => quote.status === "sent");
              const agreement = agreements.find((row) => row.status === "sent");
              return (
                <article className="soft-panel p-4" key={String(plan.id)}>
                  <div className="flex flex-wrap justify-between gap-3">
                    <div>
                      <p className="font-semibold">
                        {String(plan.title ?? plan.reference)}
                      </p>
                      <p className="mt-1 text-sm text-muted">
                        {String(plan.reference)} · Wageni{" "}
                        {String(plan.attendance)}
                      </p>
                    </div>
                    <span className="rounded-full bg-brand-green-soft px-3 py-1 text-sm font-semibold">
                      {String(plan.status).replaceAll("_", " ")}
                    </span>
                  </div>
                  {sent ? (
                    <div className="mt-4 rounded-2xl border border-brand-border p-4">
                      <p className="font-semibold">
                        Quotation #{String(sent.revision)} · TZS{" "}
                        {Number(sent.total_tzs ?? 0).toLocaleString()}
                      </p>
                      <p className="mt-1 text-sm text-muted">
                        Inaisha:{" "}
                        {new Date(String(sent.expires_at)).toLocaleString()}
                      </p>
                      <button
                        className="btn btn-success mt-3"
                        disabled={busy}
                        onClick={() => void acceptEventQuote(String(sent.id))}
                      >
                        Kubali quotation
                      </button>
                    </div>
                  ) : null}
                  {agreement ? (
                    <div className="mt-4 rounded-2xl border border-brand-border p-4">
                      <p className="font-semibold">
                        Makubaliano ya mwisho · Version{" "}
                        {String(agreement.version)}
                      </p>
                      <p className="mt-2 whitespace-pre-line text-sm text-muted">
                        {String(agreement.terms)}
                      </p>
                      <button
                        className="btn btn-success mt-3"
                        disabled={busy}
                        onClick={() =>
                          void acceptEventAgreement(String(agreement.id))
                        }
                      >
                        Kubali makubaliano
                      </button>
                    </div>
                  ) : null}
                  {plan.status === "payment_pending" ? (
                    <button
                      className="btn btn-success mt-4"
                      disabled={busy}
                      onClick={() => void pay("event_deposit", String(plan.id))}
                    >
                      Lipa deposit na thibitisha tukio
                    </button>
                  ) : null}
                  {!sent &&
                  !agreement &&
                  !["confirmed", "payment_pending"].includes(
                    String(plan.status),
                  ) ? (
                    <p className="mt-3 text-sm text-muted">
                      Quotation au makubaliano bado yanaandaliwa.
                    </p>
                  ) : null}
                </article>
              );
            })
          )}
        </div>
      </section>
      <p className="mt-6 text-sm text-muted">
        Need to remove your account?{" "}
        <Link className="font-semibold underline" href="/delete-account">
          Open account deletion
        </Link>
        .
      </p>
    </section>
  );
}

function AccountAction({ href, title }: { href: string; title: string }) {
  return (
    <Link
      href={href}
      className="soft-panel block p-4 transition hover:-translate-y-0.5 hover:shadow-md"
    >
      <p className="font-semibold text-brand-navy">{title}</p>
    </Link>
  );
}

function readError(error: unknown) {
  return error instanceof Error
    ? error.message
    : "The request could not be completed.";
}

function assignedAgentName(booking: BookingRow) {
  const agent = Array.isArray(booking.agents)
    ? booking.agents[0]
    : booking.agents;
  return agent?.display_name ?? agent?.business_name ?? booking.agent_id;
}
