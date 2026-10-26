"use client";

import Link from "next/link";
import { FormEvent, useCallback, useEffect, useState } from "react";
import { getBrowserSupabase } from "@/lib/supabase-browser";

type Row = Record<string, unknown>;
type Tab =
  | "dashboard"
  | "assets"
  | "bookings"
  | "tenants"
  | "agreements"
  | "statements"
  | "policies"
  | "move-outs";
const tabs: Array<[Tab, string]> = [
  ["dashboard", "Dashboard"],
  ["assets", "My Assets"],
  ["bookings", "Bookings"],
  ["tenants", "Tenants & Renters"],
  ["agreements", "Rental Agreements"],
  ["statements", "Payments & Statements"],
  ["policies", "Booking Policies"],
  ["move-outs", "Move-out Notices"],
];

export function OwnerPortal({
  initialType = "individual",
}: {
  initialType?: string;
}) {
  const supabase = getBrowserSupabase();
  const [userId, setUserId] = useState<string | null>(null);
  const [owner, setOwner] = useState<Row | null>(null);
  const [application, setApplication] = useState<Row | null>(null);
  const [tab, setTab] = useState<Tab>("dashboard");
  const [data, setData] = useState<Record<string, Row[]>>({});
  const [notice, setNotice] = useState("Loading owner workspace...");
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    const { data: auth } = await supabase.auth.getUser();
    if (!auth.user) {
      setUserId(null);
      setNotice("Sign in with your KODIMALI account to continue.");
      return;
    }
    setUserId(auth.user.id);
    const [ownerResult, applicationResult] = await Promise.all([
      supabase
        .from("owner_profiles")
        .select("*")
        .eq("profile_id", auth.user.id)
        .maybeSingle(),
      supabase
        .from("owner_applications")
        .select("*")
        .eq("applicant_id", auth.user.id)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle(),
    ]);
    if (ownerResult.error) throw ownerResult.error;
    if (applicationResult.error) throw applicationResult.error;
    const ownerRow = ownerResult.data as unknown as Row | null;
    setOwner(ownerRow);
    setApplication(applicationResult.data as unknown as Row | null);
    if (!ownerRow || ownerRow.verification_status !== "verified") {
      setNotice("");
      return;
    }
    const ownerId = String(ownerRow.id);
    const results = await Promise.all([
      supabase
        .from("owner_asset_claims")
        .select("*, rental_assets(display_name,category,verification_status)")
        .eq("owner_id", ownerId),
      supabase
        .from("booking_requests")
        .select(
          "id,request_reference,booking_status,owner_approval_status,requested_start_at,requested_end_at,customer_name,listings(title,asset_id)",
        )
        .order("created_at", { ascending: false }),
      supabase
        .from("tenant_invitations")
        .select("*, rental_assets(display_name)")
        .eq("owner_id", ownerId)
        .order("created_at", { ascending: false }),
      supabase
        .from("rental_agreements")
        .select("*, rental_assets(display_name)")
        .eq("owner_id", ownerId)
        .order("created_at", { ascending: false }),
      supabase
        .from("owner_statement_entries")
        .select("*")
        .eq("owner_id", ownerId)
        .order("occurred_at", { ascending: false }),
      supabase
        .from("booking_policies")
        .select("*")
        .eq("owner_id", ownerId)
        .order("created_at", { ascending: false }),
      supabase
        .from("tenant_move_out_notices")
        .select("*, rental_agreements(asset_id,rental_assets(display_name))")
        .order("created_at", { ascending: false }),
      supabase
        .from("owner_booking_agreement_versions")
        .select("*")
        .eq("is_active", true)
        .order("version", { ascending: false }),
      supabase
        .from("owner_booking_agreement_acceptances")
        .select("*")
        .eq("owner_id", ownerId),
    ]);
    const names = [
      "assets",
      "bookings",
      "tenants",
      "agreements",
      "statements",
      "policies",
      "moveOuts",
      "agreementVersions",
      "acceptances",
    ];
    const next: Record<string, Row[]> = {};
    results.forEach((result, index) => {
      if (result.error) throw result.error;
      next[names[index]] = (result.data ?? []) as Row[];
    });
    setData(next);
    setNotice("");
  }, [supabase]);

  useEffect(() => {
    const timer = window.setTimeout(
      () => void load().catch((error) => setNotice(readError(error))),
      0,
    );
    return () => window.clearTimeout(timer);
  }, [load]);

  async function apply(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    const form = new FormData(event.currentTarget);
    const { error } = await supabase.rpc("apply_for_owner_access", {
      p_owner_type: form.get("type"),
      p_legal_name: form.get("name"),
      p_phone_number: form.get("phone"),
      p_authorization_summary: form.get("authority"),
      p_document_paths: [],
    } as never);
    setBusy(false);
    if (error) setNotice(error.message);
    else {
      setNotice("Application submitted for secure review.");
      await load();
    }
  }
  async function respond(id: string, approve: boolean) {
    setBusy(true);
    const { error } = await supabase.rpc("owner_respond_to_booking", {
      p_booking_request_id: id,
      p_approve: approve,
    } as never);
    setBusy(false);
    setNotice(
      error?.message ?? (approve ? "Booking approved." : "Booking declined."),
    );
    if (!error) await load();
  }
  async function acceptAgreement(id: string) {
    setBusy(true);
    const { error } = await supabase.rpc("accept_owner_booking_agreement", {
      p_agreement_version_id: id,
    } as never);
    setBusy(false);
    setNotice(
      error?.message ?? "Owner booking agreement accepted and recorded.",
    );
    if (!error) await load();
  }
  async function claimListing(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    const form = new FormData(event.currentTarget);
    const raw = String(form.get("listing") ?? "")
      .trim()
      .replace(/\/$/, "");
    const listingId = raw.split("/").pop() ?? raw;
    const { error } = await supabase.rpc("submit_owner_listing_claim", {
      p_listing_id: listingId,
      p_authority_type: form.get("authority"),
      p_evidence_paths: [],
    } as never);
    setBusy(false);
    setNotice(
      error?.message ??
        "Asset claim submitted. An administrator must verify the item and your authority before bookings open.",
    );
    if (!error) await load();
  }
  async function savePolicy(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    const form = new FormData(event.currentTarget);
    const assetId = String(form.get("assetId"));
    const asset = (data.assets ?? []).find((row) => row.asset_id === assetId);
    const category = relation(asset?.rental_assets)?.category;
    const { error } = await supabase
      .from("booking_policies")
      .insert({
        owner_id: owner!.id,
        asset_id: assetId,
        category,
        version: Number(form.get("version")),
        title: form.get("title"),
        body: form.get("body"),
        approval_mode: form.get("approvalMode"),
        minimum_notice_hours: Number(form.get("noticeHours")),
        cancellation_configuration: { summary: form.get("cancellation") },
        fee_configuration: { collection_enabled: false },
        active_from: new Date().toISOString(),
        is_active: true,
      } as never);
    setBusy(false);
    setNotice(
      error?.message ??
        "Booking policy saved. Paid booking stays disabled until the owner agreement and payment activation requirements are satisfied.",
    );
    if (!error) await load();
  }
  async function inviteTenant(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    const form = new FormData(event.currentTarget);
    const { data: result, error } = await supabase.rpc("invite_tenant", {
      p_asset_id: form.get("assetId"),
      p_email: form.get("email") || null,
      p_phone_number: form.get("phone") || null,
    } as never);
    setBusy(false);
    setNotice(
      error?.message ??
        `Invitation created. Secure token: ${String((result as Row | null)?.token ?? "")}`,
    );
    if (!error) await load();
  }
  async function createRentalAgreement(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    const form = new FormData(event.currentTarget);
    const { error } = await supabase.rpc(
      "create_rental_agreement_from_invitation",
      {
        p_invitation_id: form.get("invitationId"),
        p_starts_on: form.get("startsOn"),
        p_ends_on: form.get("endsOn") || null,
        p_rent_amount_tzs: Number(form.get("rent")),
        p_rent_period: form.get("period"),
        p_terms: { summary: form.get("terms") },
      } as never,
    );
    setBusy(false);
    setNotice(
      error?.message ?? "Rental agreement sent to the renter for acceptance.",
    );
    if (!error) await load();
  }

  if (!userId)
    return (
      <section className="surface-card p-8">
        <p>{notice}</p>
        <Link href="/login?next=/owner" className="btn btn-success mt-5">
          Sign in
        </Link>
      </section>
    );
  if (!owner || owner.verification_status !== "verified")
    return (
      <Application
        application={application}
        busy={busy}
        notice={notice}
        submit={apply}
        initialType={initialType}
      />
    );
  return (
    <div className="grid gap-6 lg:grid-cols-[250px_1fr]">
      <aside className="navy-panel h-fit p-5 lg:sticky lg:top-28">
        <p className="eyebrow !text-brand-amber">Owner workspace</p>
        <h1 className="mt-2 font-heading text-2xl font-semibold text-white">
          {String(owner.display_name)}
        </h1>
        <div className="mt-6 grid gap-2">
          {tabs.map(([id, label]) => (
            <button
              key={id}
              className={`rounded-2xl px-4 py-3 text-left text-sm font-bold ${tab === id ? "bg-brand-amber text-brand-navy" : "text-white/75 hover:bg-white/10"}`}
              onClick={() => setTab(id)}
            >
              {label}
            </button>
          ))}
        </div>
        <Link className="btn btn-outline mt-5 w-full" href="/manage">
          Switch workspace
        </Link>
      </aside>
      <main>
        {notice ? (
          <p className="mb-4 rounded-2xl bg-brand-info-soft p-4" role="status">
            {notice}
          </p>
        ) : null}
        {tab === "dashboard" ? <Dashboard data={data} /> : null}
        {tab === "assets" ? (
          <OwnerAssets rows={data.assets} busy={busy} claim={claimListing} />
        ) : null}
        {tab === "bookings" ? (
          <Bookings rows={data.bookings} busy={busy} respond={respond} />
        ) : null}
        {tab === "tenants" ? (
          <Tenants
            rows={data.tenants}
            assets={data.assets}
            busy={busy}
            invite={inviteTenant}
            createAgreement={createRentalAgreement}
          />
        ) : null}
        {tab === "agreements" ? (
          <Rows title="Rental agreements" rows={data.agreements} />
        ) : null}
        {tab === "statements" ? (
          <Rows title="Payments and statements" rows={data.statements} />
        ) : null}
        {tab === "policies" ? (
          <Policies
            versions={data.agreementVersions}
            acceptances={data.acceptances}
            policies={data.policies}
            assets={data.assets}
            busy={busy}
            accept={acceptAgreement}
            save={savePolicy}
          />
        ) : null}
        {tab === "move-outs" ? (
          <Rows title="Move-out notices" rows={data.moveOuts} />
        ) : null}
      </main>
    </div>
  );
}

function Application({
  application,
  busy,
  notice,
  submit,
  initialType,
}: {
  application: Row | null;
  busy: boolean;
  notice: string;
  submit: (event: FormEvent<HTMLFormElement>) => void;
  initialType: string;
}) {
  if (
    application &&
    ["submitted", "under_review"].includes(String(application.status))
  )
    return (
      <section className="surface-card mx-auto max-w-2xl p-8">
        <p className="eyebrow">Owner access</p>
        <h1 className="mt-3 font-heading text-3xl font-semibold">
          Application under review
        </h1>
        <p className="mt-4 text-muted">
          Status: {String(application.status).replaceAll("_", " ")}. Your
          private evidence is visible only to authorized reviewers.
        </p>
      </section>
    );
  return (
    <section className="surface-card mx-auto max-w-2xl p-8">
      <p className="eyebrow">Owner and manager access</p>
      <h1 className="mt-3 font-heading text-3xl font-semibold">
        Apply for a business workspace
      </h1>
      <p className="mt-3 text-muted">
        Hall owners choose “Hall or venue owner”. A manager operating a hall for
        someone else chooses “Authorized manager” and describes their authority
        for verification.
      </p>
      <form className="mt-6 grid gap-4" onSubmit={submit}>
        <label className="field-label">
          Owner or manager type
          <select
            name="type"
            className="field-input mt-2"
            defaultValue={initialType}
          >
            <option value="individual">Individual owner</option>
            <option value="vehicle_owner">Vehicle owner</option>
            <option value="venue_owner">Hall or venue owner</option>
            <option value="equipment_owner">Equipment owner</option>
            <option value="authorized_manager">Authorized manager</option>
          </select>
        </label>
        <label className="field-label">
          Legal name
          <input name="name" className="field-input mt-2" required />
        </label>
        <label className="field-label">
          Phone number
          <input name="phone" className="field-input mt-2" required />
        </label>
        <label className="field-label">
          Describe your ownership or management authority
          <textarea
            name="authority"
            className="field-input mt-2 min-h-28"
            required
          />
        </label>
        <button className="btn btn-success" disabled={busy}>
          Submit for verification
        </button>
      </form>
      {notice ? <p className="mt-4 text-sm text-muted">{notice}</p> : null}
    </section>
  );
}
function Dashboard({ data }: { data: Record<string, Row[]> }) {
  const cards = [
    ["Assets", data.assets?.length],
    ["Bookings", data.bookings?.length],
    ["Tenants", data.tenants?.length],
    ["Statements", data.statements?.length],
  ];
  return (
    <>
      <section className="owner-hero rounded-[28px] p-8 text-white">
        <p className="eyebrow !text-brand-amber">Overview</p>
        <h2 className="mt-3 font-heading text-4xl font-semibold">
          Your rental business
        </h2>
        <p className="mt-3 max-w-xl text-white/70">
          Verified assets, booking decisions and financial records in one secure
          workspace.
        </p>
      </section>
      <div className="mt-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {cards.map(([label, value]) => (
          <article className="surface-card p-5" key={String(label)}>
            <p className="text-sm text-muted">{label}</p>
            <p className="mt-2 font-heading text-3xl font-semibold">
              {value ?? 0}
            </p>
          </article>
        ))}
      </div>
    </>
  );
}
function Rows({ title, rows = [] }: { title: string; rows?: Row[] }) {
  return (
    <section className="surface-card p-6">
      <h2 className="font-heading text-2xl font-semibold">{title}</h2>
      <div className="mt-5 grid gap-3">
        {rows.length ? (
          rows.map((row) => (
            <article className="soft-panel p-4" key={String(row.id)}>
              <p className="font-semibold">
                {String(
                  row.display_name ??
                    row.request_reference ??
                    row.entry_type ??
                    row.status ??
                    row.id,
                )}
              </p>
              <p className="mt-1 text-sm text-muted">
                {String(
                  row.status ?? row.verification_status ?? "recorded",
                ).replaceAll("_", " ")}
              </p>
            </article>
          ))
        ) : (
          <p className="text-muted">Nothing found.</p>
        )}
      </div>
    </section>
  );
}
function OwnerAssets({
  rows = [],
  busy,
  claim,
}: {
  rows?: Row[];
  busy: boolean;
  claim: (event: FormEvent<HTMLFormElement>) => void;
}) {
  return (
    <div className="grid gap-6">
      <section className="surface-card p-6">
        <h2 className="font-heading text-2xl font-semibold">Connect an item</h2>
        <p className="mt-2 text-sm text-muted">
          Paste its KODIMALI listing link or listing ID. Your identity,
          authority and the physical item must all be verified before it can
          accept bookings.
        </p>
        <form className="mt-5 grid gap-4 sm:grid-cols-2" onSubmit={claim}>
          <label className="field-label sm:col-span-2">
            Listing link or ID
            <input name="listing" className="field-input mt-2" required />
          </label>
          <label className="field-label">
            Your authority
            <select name="authority" className="field-input mt-2">
              <option value="owner">Owner</option>
              <option value="authorized_manager">Authorized manager</option>
            </select>
          </label>
          <button className="btn btn-success self-end" disabled={busy}>
            Submit for verification
          </button>
        </form>
      </section>
      <Rows title="My asset claims" rows={rows} />
    </div>
  );
}
function Bookings({
  rows = [],
  busy,
  respond,
}: {
  rows?: Row[];
  busy: boolean;
  respond: (id: string, approve: boolean) => void;
}) {
  return (
    <section className="surface-card p-6">
      <h2 className="font-heading text-2xl font-semibold">Booking requests</h2>
      <div className="mt-5 grid gap-4">
        {rows.length ? (
          rows.map((row) => (
            <article className="soft-panel p-5" key={String(row.id)}>
              <p className="font-semibold">{String(row.request_reference)}</p>
              <p className="mt-2 text-sm text-muted">
                {String(row.customer_name)} ·{" "}
                {new Date(String(row.requested_start_at)).toLocaleString()} –{" "}
                {new Date(String(row.requested_end_at)).toLocaleString()}
              </p>
              <p className="mt-2 text-sm font-semibold">
                Owner approval:{" "}
                {String(row.owner_approval_status).replaceAll("_", " ")}
              </p>
              {row.owner_approval_status === "pending" ? (
                <div className="mt-4 flex gap-2">
                  <button
                    className="btn btn-success"
                    disabled={busy}
                    onClick={() => void respond(String(row.id), true)}
                  >
                    Approve
                  </button>
                  <button
                    className="btn btn-outline"
                    disabled={busy}
                    onClick={() => void respond(String(row.id), false)}
                  >
                    Decline
                  </button>
                </div>
              ) : null}
            </article>
          ))
        ) : (
          <p className="text-muted">Nothing found.</p>
        )}
      </div>
    </section>
  );
}
function Tenants({
  rows = [],
  assets = [],
  busy,
  invite,
  createAgreement,
}: {
  rows?: Row[];
  assets?: Row[];
  busy: boolean;
  invite: (event: FormEvent<HTMLFormElement>) => void;
  createAgreement: (event: FormEvent<HTMLFormElement>) => void;
}) {
  const accepted = rows.filter((row) => row.status === "accepted");
  return (
    <div className="grid gap-6">
      <section className="surface-card p-6">
        <h2 className="font-heading text-2xl font-semibold">Invite a tenant</h2>
        <p className="mt-2 text-sm text-muted">
          The tenant must accept with their own KODIMALI account.
        </p>
        <form className="mt-5 grid gap-4 sm:grid-cols-2" onSubmit={invite}>
          <label className="field-label sm:col-span-2">
            Verified asset
            <select className="field-input mt-2" name="assetId" required>
              <option value="">Choose asset</option>
              {assets
                .filter((row) => row.status === "verified")
                .map((row) => (
                  <option value={String(row.asset_id)} key={String(row.id)}>
                    {String(
                      relation(row.rental_assets)?.display_name ?? row.asset_id,
                    )}
                  </option>
                ))}
            </select>
          </label>
          <label className="field-label">
            Email
            <input className="field-input mt-2" name="email" type="email" />
          </label>
          <label className="field-label">
            Phone
            <input className="field-input mt-2" name="phone" />
          </label>
          <button className="btn btn-success sm:col-span-2" disabled={busy}>
            Create secure invitation
          </button>
        </form>
      </section>
      <section className="surface-card p-6">
        <h2 className="font-heading text-2xl font-semibold">
          Create rental agreement
        </h2>
        <p className="mt-2 text-sm text-muted">
          Available after the renter accepts an invitation.
        </p>
        <form
          className="mt-5 grid gap-4 sm:grid-cols-2"
          onSubmit={createAgreement}
        >
          <label className="field-label sm:col-span-2">
            Accepted invitation
            <select className="field-input mt-2" name="invitationId" required>
              <option value="">Choose renter</option>
              {accepted.map((row) => (
                <option key={String(row.id)} value={String(row.id)}>
                  {String(row.email ?? row.phone_number ?? row.id)}
                </option>
              ))}
            </select>
          </label>
          <label className="field-label">
            Start date
            <input
              className="field-input mt-2"
              name="startsOn"
              type="date"
              required
            />
          </label>
          <label className="field-label">
            End date (optional)
            <input className="field-input mt-2" name="endsOn" type="date" />
          </label>
          <label className="field-label">
            Rent amount (TZS)
            <input
              className="field-input mt-2"
              name="rent"
              type="number"
              min="0"
              required
            />
          </label>
          <label className="field-label">
            Rent period
            <select className="field-input mt-2" name="period">
              <option value="month">Monthly</option>
              <option value="week">Weekly</option>
              <option value="day">Daily</option>
              <option value="year">Yearly</option>
            </select>
          </label>
          <label className="field-label sm:col-span-2">
            Agreement terms
            <textarea
              className="field-input mt-2 min-h-28"
              name="terms"
              required
            />
          </label>
          <button
            className="btn btn-success sm:col-span-2"
            disabled={busy || accepted.length === 0}
          >
            Send agreement to renter
          </button>
        </form>
      </section>
      <Rows title="Tenant invitations" rows={rows} />
    </div>
  );
}
function Policies({
  versions = [],
  acceptances = [],
  policies = [],
  assets = [],
  busy,
  accept,
  save,
}: {
  versions?: Row[];
  acceptances?: Row[];
  policies?: Row[];
  assets?: Row[];
  busy: boolean;
  accept: (id: string) => void;
  save: (event: FormEvent<HTMLFormElement>) => void;
}) {
  const active = versions[0];
  const accepted =
    active && acceptances.some((row) => row.agreement_version_id === active.id);
  return (
    <div className="grid gap-6">
      <section className="surface-card p-6">
        <h2 className="font-heading text-2xl font-semibold">
          Owner booking agreement
        </h2>
        {active ? (
          <>
            <h3 className="mt-4 font-semibold">
              {String(active.title)} · Version {String(active.version)}
            </h3>
            <p className="mt-3 whitespace-pre-line text-sm text-muted">
              {String(active.body)}
            </p>
            {accepted ? (
              <p className="mt-4 font-semibold text-brand-green">
                Accepted and recorded
              </p>
            ) : (
              <button
                className="btn btn-success mt-5"
                disabled={busy}
                onClick={() => void accept(String(active.id))}
              >
                Accept agreement
              </button>
            )}
          </>
        ) : (
          <p className="mt-4 text-muted">No active agreement version.</p>
        )}
      </section>
      <section className="surface-card p-6">
        <h2 className="font-heading text-2xl font-semibold">
          Create booking policy
        </h2>
        <form className="mt-5 grid gap-4 sm:grid-cols-2" onSubmit={save}>
          <label className="field-label sm:col-span-2">
            Asset
            <select name="assetId" className="field-input mt-2" required>
              <option value="">Choose verified asset</option>
              {assets
                .filter((row) => row.status === "verified")
                .map((row) => (
                  <option key={String(row.id)} value={String(row.asset_id)}>
                    {String(
                      relation(row.rental_assets)?.display_name ?? row.asset_id,
                    )}
                  </option>
                ))}
            </select>
          </label>
          <label className="field-label">
            Policy version
            <input
              className="field-input mt-2"
              name="version"
              type="number"
              min="1"
              defaultValue="1"
              required
            />
          </label>
          <label className="field-label">
            Approval
            <select className="field-input mt-2" name="approvalMode">
              <option value="manual">Manual approval</option>
              <option value="automatic">Automatic after conditions</option>
            </select>
          </label>
          <label className="field-label">
            Title
            <input className="field-input mt-2" name="title" required />
          </label>
          <label className="field-label">
            Minimum notice hours
            <input
              className="field-input mt-2"
              name="noticeHours"
              type="number"
              min="0"
              defaultValue="2"
            />
          </label>
          <label className="field-label sm:col-span-2">
            Booking conditions
            <textarea
              className="field-input mt-2 min-h-28"
              name="body"
              required
            />
          </label>
          <label className="field-label sm:col-span-2">
            Cancellation and refund rule
            <textarea
              className="field-input mt-2 min-h-24"
              name="cancellation"
              required
            />
          </label>
          <button className="btn btn-success sm:col-span-2" disabled={busy}>
            Save policy
          </button>
        </form>
      </section>
      <Rows title="Asset booking policies" rows={policies} />
    </div>
  );
}
function relation(value: unknown): Row | null {
  if (Array.isArray(value)) return (value[0] as Row | undefined) ?? null;
  return value && typeof value === "object" ? (value as Row) : null;
}
function readError(error: unknown) {
  return error instanceof Error
    ? error.message
    : "The owner workspace could not be loaded.";
}
