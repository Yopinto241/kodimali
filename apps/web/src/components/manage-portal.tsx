"use client";

import Link from "next/link";
import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { User } from "@supabase/supabase-js";
import { getBrowserSupabase } from "@/lib/supabase-browser";
import { PageShell } from "@/components/page-shell";

type Row = Record<string, unknown>;
type Role = "admin" | "agent";
type Tab = "dashboard" | "listings" | "add-listing" | "requests" | "categories" | "agents" | "users" | "locations" | "reports" | "promotions" | "notifications" | "profile";

const bookingStatuses = [
  "new", "checking_availability", "contacted", "viewing_scheduled",
  "reserved", "confirmed", "completed", "cancelled", "rejected",
  "no_response", "agent_delayed",
];

export function ManagePortal() {
  const supabase = useMemo(() => getBrowserSupabase(), []);
  const [user, setUser] = useState<User | null>(null);
  const [role, setRole] = useState<Role | null>(null);
  const [agentId, setAgentId] = useState<string | null>(null);
  const [tab, setTab] = useState<Tab>("dashboard");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [listings, setListings] = useState<Row[]>([]);
  const [bookings, setBookings] = useState<Row[]>([]);
  const [categories, setCategories] = useState<Row[]>([]);
  const [agents, setAgents] = useState<Row[]>([]);
  const [users, setUsers] = useState<Row[]>([]);
  const [extraRows, setExtraRows] = useState<Partial<Record<Tab, Row[]>>>({});
  const [counts, setCounts] = useState<Row>({});
  const [tabLoading, setTabLoading] = useState(false);
  const [online, setOnline] = useState(() =>
    typeof navigator === "undefined" ? true : navigator.onLine,
  );
  const [hasMore, setHasMore] = useState<Partial<Record<Tab, boolean>>>({});
  const [editingListing, setEditingListing] = useState<Row | null>(null);
  const [editingCategory, setEditingCategory] = useState<Row | null>(null);
  const activeUserId = useRef<string | null>(null);
  const loadedTabs = useRef<Set<Tab>>(new Set());

  const loadDashboardCounts = useCallback(async () => {
    try {
      const result = await withRetry(() =>
        supabase.rpc("get_manage_dashboard_counts"),
      );
      if (result.error) throw result.error;
      const value = Array.isArray(result.data) ? result.data[0] : result.data;
      setCounts((value as unknown as Row | null) ?? {});
    } catch {
      // This fallback keeps the portal useful before the companion migration
      // has been applied to an older Supabase environment.
      const [listingResult, bookingResult, agentResult] = await Promise.all([
        supabase.from("listings").select("id", { count: "exact", head: true }),
        supabase.from("booking_requests").select("id", { count: "exact", head: true }),
        supabase.from("agents").select("id", { count: "exact", head: true }),
      ]);
      setCounts({
        listings: listingResult.count ?? 0,
        requests: bookingResult.count ?? 0,
        agents: agentResult.count ?? 0,
      });
    }
  }, [supabase]);

  const loadWorkspace = useCallback(async (nextUser: User) => {
    setLoading(true);
    setMessage(null);
    try {
      const { data: roleRows, error: roleError } = await supabase
        .from("user_roles").select("role").eq("profile_id", nextUser.id);
      if (roleError) throw roleError;
      const roles = ((roleRows ?? []) as unknown as { role: string }[]).map(
        (item) => item.role,
      );
      const nextRole: Role | null = roles.includes("admin")
        ? "admin"
        : roles.includes("agent") ? "agent" : null;
      setRole(nextRole);
      if (!nextRole) {
        setMessage("This account is not an administrator or agent account.");
        setLoading(false);
        return;
      }

      let nextAgentId: string | null = null;
      if (nextRole === "agent") {
        const { data: agent, error } = await supabase
          .from("agents").select("id").eq("profile_id", nextUser.id).maybeSingle();
        if (error) throw error;
        nextAgentId = (agent as unknown as { id?: string } | null)?.id ?? null;
      }
      setAgentId(nextAgentId);
      loadedTabs.current.clear();
      setLoading(false);
      void loadDashboardCounts();
    } catch (error) {
      setMessage(readError(error));
    } finally {
      setLoading(false);
    }
  }, [loadDashboardCounts, supabase]);

  const loadTabData = useCallback(async (target: Tab, append = false) => {
    if (target === "dashboard" || !role) return;
    if (!append && loadedTabs.current.has(target)) return;
    setTabLoading(true);
    setMessage(null);
    try {
      const currentLength = target === "listings" ? listings.length
        : target === "requests" ? bookings.length
        : target === "categories" ? categories.length
        : target === "agents" ? agents.length
        : target === "users" ? users.length : (extraRows[target]?.length ?? 0);
      const from = append ? currentLength : 0;
      const to = from + 19;
      let result;
      if (target === "listings") {
        let query = supabase.from("listings").select(
          "id, agent_id, title, description, price_amount, price_period, deposit_required_amount, listing_rules, public_location_label, status, approval_status, availability_status, listing_attributes, created_at, asset_categories(id, name, slug, field_schema)",
        ).order("created_at", { ascending: false }).range(from, to);
        if (role === "agent" && agentId) query = query.eq("agent_id", agentId);
        result = await withRetry(() => query);
      } else if (target === "requests") {
        let query = supabase.from("booking_requests").select(
          "id, agent_id, request_reference, customer_name, customer_phone_number, requested_start_at, requested_end_at, request_message, booking_status, created_at, listings(title)",
        ).order("created_at", { ascending: false }).range(from, to);
        if (role === "agent" && agentId) query = query.eq("agent_id", agentId);
        result = await withRetry(() => query);
      } else if (target === "categories") {
        result = await withRetry(() => supabase.from("asset_categories").select(
          "id, name, slug, description, display_order, is_active, home_feed_weight, field_schema",
        ).order("display_order").range(from, to));
      } else if (target === "agents") {
        result = await withRetry(() => supabase.from("agents").select(
          "id, profile_id, display_name, business_name, phone_number, contact_email, verification_status, account_status, created_at",
        ).order("created_at", { ascending: false }).range(from, to));
      } else if (target === "users") {
        result = await withRetry(() => supabase.rpc("get_admin_customer_users", {
          p_offset: from, p_limit: 20,
        } as never));
      } else if (target === "locations") {
        result = await withRetry(() => supabase.from("locations").select(
          "id, parent_id, name, location_type, is_active, created_at",
        ).order("location_type").order("name").range(from, to));
      } else if (target === "reports") {
        result = await withRetry(() => supabase.from("reports").select(
          "id, listing_id, report_reason, details, status, created_at",
        ).order("created_at", { ascending: false }).range(from, to));
      } else if (target === "promotions") {
        result = await withRetry(() => supabase.from("platform_promotions").select(
          "id, title, description, placement, visibility_scope, is_active, start_at, end_at, created_at",
        ).order("created_at", { ascending: false }).range(from, to));
      } else if (target === "notifications") {
        result = await withRetry(() => supabase.from("notifications").select(
          "id, title, body, type, read_at, created_at",
        ).eq("user_id", user!.id).order("created_at", { ascending: false }).range(from, to));
      } else if (target === "profile") {
        result = await withRetry(() => supabase.from("profiles").select(
          "id, full_name, username, account_email, phone_number, preferred_language, created_at",
        ).eq("id", user!.id).limit(1));
      } else {
        return;
      }
      if (result.error) throw result.error;
      const rows = (result.data ?? []) as unknown as Row[];
      if (target === "listings") setListings((old) => append ? [...old, ...rows] : rows);
      if (target === "requests") setBookings((old) => append ? [...old, ...rows] : rows);
      if (target === "categories") setCategories((old) => append ? [...old, ...rows] : rows);
      if (target === "agents") setAgents((old) => append ? [...old, ...rows] : rows);
      if (target === "users") setUsers((old) => append ? [...old, ...rows] : rows);
      if (!["listings", "requests", "categories", "agents", "users"].includes(target)) {
        setExtraRows((old) => ({ ...old, [target]: append ? [...(old[target] ?? []), ...rows] : rows }));
      }
      loadedTabs.current.add(target);
      setHasMore((old) => ({ ...old, [target]: rows.length === 20 }));
    } catch (error) {
      setMessage(`${readError(error)} Check your connection and retry.`);
    } finally {
      setTabLoading(false);
    }
  }, [agentId, agents.length, bookings.length, categories.length, extraRows, listings.length, role, supabase, user, users.length]);

  useEffect(() => {
    const applyUser = (nextUser: User | null) => {
      setUser(nextUser);
      if (nextUser && activeUserId.current !== nextUser.id) {
        activeUserId.current = nextUser.id;
        void loadWorkspace(nextUser);
      }
      else {
        if (!nextUser) {
          activeUserId.current = null;
          setRole(null);
          setLoading(false);
        }
      }
    };
    // getSession reads the locally persisted session immediately. Every data
    // query is still authorized by Supabase RLS, so page startup need not wait
    // for a separate remote getUser round trip.
    void supabase.auth.getSession().then(({ data }) =>
      applyUser(data.session?.user ?? null),
    );
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      applyUser(session?.user ?? null);
    });
    return () => data.subscription.unsubscribe();
  }, [loadWorkspace, supabase]);

  useEffect(() => {
    const updateConnection = () => setOnline(navigator.onLine);
    window.addEventListener("online", updateConnection);
    window.addEventListener("offline", updateConnection);
    return () => {
      window.removeEventListener("online", updateConnection);
      window.removeEventListener("offline", updateConnection);
    };
  }, []);

  async function signIn(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setMessage(null);
    const { error } = await supabase.auth.signInWithPassword({
      email: email.trim(), password,
    });
    if (error) setMessage(error.message);
    setBusy(false);
  }

  async function refresh() {
    if (tab === "dashboard") {
      await loadDashboardCounts();
      return;
    }
    loadedTabs.current.delete(tab);
    await loadTabData(tab);
  }

  async function moderateListing(listingId: string, status: "active" | "inactive") {
    await perform(async () => {
      const { error } = await supabase.functions.invoke("approve-listing", {
        body: { listingId, status, availabilityStatus: "available" },
      });
      if (error) throw error;
      await refresh();
    }, `Listing changed to ${status}.`);
  }

  async function updateBooking(bookingId: string, status: string) {
    await perform(async () => {
      const rpcResult = await supabase.rpc("manage_update_booking_status", {
        p_booking_id: bookingId,
        p_status: status,
      } as never);
      if (rpcResult.error) {
        if (!isMissingFunction(rpcResult.error)) throw rpcResult.error;
        const fallback = await supabase.from("booking_requests")
          .update({ booking_status: status } as never).eq("id", bookingId);
        if (fallback.error) throw fallback.error;
      }
      setBookings((current) => current.map((item) =>
        item.id === bookingId ? { ...item, booking_status: status } : item));
    }, "Request status updated.");
  }

  async function updateAgent(id: string, activate: boolean) {
    await perform(async () => {
      const { error } = await supabase.functions.invoke("verify-agent", {
        body: {
          agentId: id,
          accountStatus: activate ? "active" : "deactivated",
          verificationStatus: activate ? "approved" : "rejected",
        },
      });
      if (error) throw error;
      await refresh();
    }, activate ? "Agent approved and activated." : "Agent deactivated.");
  }

  async function updateReport(id: string, status: string) {
    await perform(async () => {
      const result = await supabase.from("reports").update({ status } as never).eq("id", id);
      if (result.error) throw result.error;
      loadedTabs.current.delete("reports"); await loadTabData("reports");
    }, "Report status updated.");
  }

  async function togglePromotion(id: string, active: boolean) {
    await perform(async () => {
      const result = await supabase.from("platform_promotions").update({ is_active: active } as never).eq("id", id);
      if (result.error) throw result.error;
      loadedTabs.current.delete("promotions"); await loadTabData("promotions");
    }, active ? "Promotion activated." : "Promotion paused.");
  }

  async function addLocation(name: string, locationType: string, parentId: string) {
    await perform(async () => {
      const result = await supabase.from("locations").insert({ name: name.trim(), location_type: locationType, parent_id: parentId || null } as never);
      if (result.error) throw result.error;
      loadedTabs.current.delete("locations"); await loadTabData("locations");
    }, "Location added.");
  }

  async function deleteLocation(id: string) {
    await perform(async () => {
      const result = await supabase.from("locations").delete().eq("id", id);
      if (result.error) throw result.error;
      loadedTabs.current.delete("locations"); await loadTabData("locations");
    }, "Location deleted.");
  }

  async function perform(action: () => Promise<void>, success: string) {
    setBusy(true);
    setMessage(null);
    try {
      await action();
      setMessage(success);
    } catch (error) {
      setMessage(readError(error));
    } finally {
      setBusy(false);
    }
  }

  if (loading) return <ManageLoading />;
  if (!user) return <ManageLogin email={email} password={password} busy={busy}
    message={message} setEmail={setEmail} setPassword={setPassword} submit={signIn} />;

  if (!role) {
    return <main className="mx-auto max-w-3xl px-4 py-16">
      <div className="surface-card p-8"><h1 className="font-heading text-3xl font-semibold">Access unavailable</h1>
      <p className="mt-3 text-muted">{message}</p>
      <button className="btn btn-outline mt-6" onClick={() => void supabase.auth.signOut()}>Sign out</button></div>
    </main>;
  }

  const tabs: { id: Tab; label: string }[] = [
    { id: "dashboard", label: "Dashboard" },
    ...(role === "admin" ? [
      { id: "users" as Tab, label: "Users" },
    ] : []),
    { id: "listings", label: "Listings" },
    ...(role === "agent" ? [{ id: "add-listing" as Tab, label: "Add asset" }] : []),
    { id: "requests", label: "Requests" },
    ...(role === "admin" ? [
      { id: "categories" as Tab, label: "Categories & fields" },
      { id: "agents" as Tab, label: "Agents" },
      { id: "locations" as Tab, label: "Locations" },
      { id: "reports" as Tab, label: "Reports" },
      { id: "promotions" as Tab, label: "Promotions" },
    ] : []),
    { id: "notifications", label: "Notifications" },
    { id: "profile", label: "Profile" },
  ];

  return <PageShell>
    <section className="mb-6 overflow-hidden rounded-[20px] bg-brand-navy px-5 py-6 text-white shadow-[0_24px_52px_rgba(11,31,58,0.16)] sm:px-8">
      <div className="flex flex-wrap items-center justify-between gap-4"><div><p className="text-xs font-bold uppercase tracking-[0.22em] text-brand-green">Secure management</p><h1 className="mt-2 font-heading text-3xl font-semibold">{role === "admin" ? "Administrator" : "Agent"} workspace</h1><p className="mt-2 text-sm text-white/75">The same KODIMALI records and permissions used by Manage Mobile.</p></div><div className="flex items-center gap-3"><span className="hidden text-sm text-white/75 sm:inline">{user.email}</span><button className="btn btn-outline" onClick={() => void supabase.auth.signOut()}>Sign out</button></div></div>
    </section>
    <div className="grid gap-6 lg:grid-cols-[250px_minmax(0,1fr)]">
      <nav className="surface-card grid h-fit grid-cols-2 gap-2 p-3 sm:grid-cols-3 lg:sticky lg:top-28 lg:flex lg:flex-col" aria-label="Management navigation">
        {tabs.map((item) => <button key={item.id} onClick={() => { setTab(item.id); void loadTabData(item.id); }}
          className={`min-w-0 rounded-xl px-3 py-3 text-center text-sm font-semibold sm:px-4 lg:text-left ${tab === item.id ? "bg-brand-navy text-white" : "hover:bg-brand-green-soft"}`}>{item.label}</button>)}
      </nav>
      <section className="min-w-0">
        {!online ? <p className="mb-4 rounded-2xl bg-brand-amber-soft p-4 text-sm font-semibold text-brand-navy">You are offline. Existing information remains visible; reconnect before saving changes.</p> : null}
        {message ? <p className="mb-4 rounded-2xl bg-brand-info-soft p-4 text-sm text-brand-navy" role="status">{message}</p> : null}
        {tab === "dashboard" ? <Dashboard role={role} counts={counts} /> : null}
        {tabLoading ? <div className="mb-4 rounded-2xl bg-brand-info-soft p-4 font-semibold">Loading this workspace...</div> : null}
        {tab === "listings" ? <Listings role={role} listings={listings} busy={busy} edit={setEditingListing} moderate={moderateListing} /> : null}
        {tab === "requests" ? <Requests bookings={bookings} busy={busy} update={updateBooking} /> : null}
        {tab === "categories" && role === "admin" ? <Categories categories={categories} edit={setEditingCategory} /> : null}
        {tab === "agents" && role === "admin" ? <Agents agents={agents} busy={busy} update={updateAgent} /> : null}
        {tab === "users" && role === "admin" ? <Users users={users} /> : null}
        {tab === "locations" && role === "admin" ? <Locations rows={extraRows.locations ?? []} busy={busy} add={addLocation} remove={deleteLocation} /> : null}
        {tab === "reports" && role === "admin" ? <Reports rows={extraRows.reports ?? []} busy={busy} update={updateReport} /> : null}
        {tab === "promotions" && role === "admin" ? <Promotions rows={extraRows.promotions ?? []} busy={busy} toggle={togglePromotion} /> : null}
        {tab === "notifications" ? <Notifications rows={extraRows.notifications ?? []} markRead={async (id) => { await supabase.from("notifications").update({ read_at: new Date().toISOString() } as never).eq("id", id); loadedTabs.current.delete("notifications"); await loadTabData("notifications"); }} /> : null}
        {tab === "profile" ? <ProfilePanel rows={extraRows.profile ?? []} email={user.email ?? ""} /> : null}
        {tab === "add-listing" && role === "agent" && agentId ? <AddListingForm agentId={agentId} onCreated={() => { loadedTabs.current.delete("listings"); setTab("listings"); void loadTabData("listings"); }} /> : null}
        {tab !== "dashboard" && hasMore[tab] ? <button className="btn btn-outline mt-4" disabled={tabLoading} onClick={() => void loadTabData(tab, true)}>{tabLoading ? "Loading..." : "Load 20 more"}</button> : null}
      </section>
    </div>
    {editingListing ? <ListingEditor listing={editingListing} close={() => setEditingListing(null)} save={(values) => perform(async () => {
      const rpcResult = await supabase.rpc("manage_update_listing_basic", {
        p_listing_id: editingListing.id,
        p_values: values,
      } as never);
      if (rpcResult.error) {
        if (!isMissingFunction(rpcResult.error)) throw rpcResult.error;
        const fallback = await supabase.from("listings").update(values as never).eq("id", editingListing.id as string);
        if (fallback.error) throw fallback.error;
      }
      setEditingListing(null); await refresh();
    }, "Listing saved.")} /> : null}
    {editingCategory ? <CategoryEditor category={editingCategory} close={() => setEditingCategory(null)} save={(values) => perform(async () => {
      const rpcResult = await supabase.rpc("manage_save_category_fields", {
        p_category_id: editingCategory.id,
        p_field_schema: values.field_schema,
      } as never);
      if (rpcResult.error) {
        if (!isMissingFunction(rpcResult.error)) throw rpcResult.error;
        const fallback = await supabase.from("asset_categories").update(values as never).eq("id", editingCategory.id as string);
        if (fallback.error) throw fallback.error;
      }
      setEditingCategory(null); await refresh();
    }, "Category fields saved.")} /> : null}
  </PageShell>;
}

function ManageLoading() {
  return <main className="grid min-h-[70vh] place-items-center"><p className="font-semibold">Loading management workspace...</p></main>;
}

function ManageLogin(props: { email: string; password: string; busy: boolean; message: string | null; setEmail: (v: string) => void; setPassword: (v: string) => void; submit: (e: FormEvent<HTMLFormElement>) => void }) {
  return <main className="mx-auto grid min-h-[80vh] max-w-6xl items-center gap-10 px-4 py-12 lg:grid-cols-2">
    <div><p className="eyebrow">Secure management access</p><h1 className="mt-3 font-heading text-5xl font-semibold text-brand-ink">Run KODIMALI from any browser.</h1>
    <p className="mt-5 max-w-xl text-lg text-muted">Agents manage listings and customer requests. Administrators moderate the marketplace, agents, categories, and dynamic listing fields.</p></div>
    <form className="surface-card grid gap-4 p-6 sm:p-8" onSubmit={props.submit}>
      <h2 className="font-heading text-2xl font-semibold">Admin or agent sign in</h2>
      <label className="grid gap-2 font-semibold">Email<input className="rounded-2xl border border-brand-border bg-white px-4 py-3" type="email" value={props.email} onChange={(e) => props.setEmail(e.target.value)} required /></label>
      <label className="grid gap-2 font-semibold">Password<input className="rounded-2xl border border-brand-border bg-white px-4 py-3" type="password" minLength={6} value={props.password} onChange={(e) => props.setPassword(e.target.value)} required /></label>
      <button className="btn btn-success" disabled={props.busy}>{props.busy ? "Signing in..." : "Sign in"}</button>
      {props.message ? <p className="rounded-xl bg-brand-info-soft p-3 text-sm">{props.message}</p> : null}
      <Link href="/" className="text-center text-sm font-semibold underline">Return to marketplace</Link>
    </form>
  </main>;
}

function Dashboard({ role, counts }: { role: Role; counts: Row }) {
  const cards = [
    ["Listings", Number(counts.listings ?? 0)],
    ["Active listings", Number(counts.active_listings ?? 0)],
    ["Open requests", Number(counts.open_requests ?? counts.requests ?? 0)],
    ...(role === "admin" ? [["Agents", Number(counts.agents ?? 0)]] : []),
  ];
  return <><div className="surface-card p-6 sm:p-8"><p className="eyebrow">Live overview</p><h2 className="mt-2 font-heading text-3xl font-semibold">Marketplace operations</h2><p className="mt-2 text-muted">The same Supabase records and permissions used by Manage Mobile, now available online.</p></div>
  <div className="mt-5 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">{cards.map(([label, value]) => <article className="soft-panel p-5" key={String(label)}><p className="text-sm font-semibold text-muted">{label}</p><p className="mt-2 font-heading text-4xl font-semibold">{value}</p></article>)}</div></>;
}

function Listings({ role, listings, busy, edit, moderate }: { role: Role; listings: Row[]; busy: boolean; edit: (row: Row) => void; moderate: (id: string, status: "active" | "inactive") => void }) {
  return <Panel title="Listings" subtitle={role === "admin" ? "Review and control marketplace visibility." : "Edit your public listing information and availability."}>
    <div className="grid gap-3">{listings.length === 0 ? <Empty text="No listings available." /> : listings.map((listing) => <article className="rounded-2xl border border-brand-border bg-white p-4" key={listing.id as string}>
      <div className="flex flex-wrap items-start justify-between gap-3"><div><h3 className="font-semibold">{listing.title as string}</h3><p className="mt-1 text-sm text-muted">{categoryName(listing)} · {String(listing.public_location_label ?? "")}</p></div><Status value={String(listing.status)} /></div>
      <div className="mt-4 flex flex-wrap gap-2"><button className="btn btn-outline" onClick={() => edit(listing)}>Edit</button>
      {role === "admin" ? <><button className="btn btn-success" disabled={busy} onClick={() => void moderate(listing.id as string, "active")}>Approve / activate</button><button className="btn btn-outline" disabled={busy} onClick={() => void moderate(listing.id as string, "inactive")}>Remove</button></> : null}</div>
    </article>)}</div>
  </Panel>;
}

function Requests({ bookings, busy, update }: { bookings: Row[]; busy: boolean; update: (id: string, status: string) => void }) {
  return <Panel title="Customer requests" subtitle="Track inquiries and keep each customer informed with current status.">
    <div className="grid gap-3">{bookings.length === 0 ? <Empty text="No customer requests yet." /> : bookings.map((booking) => <article className="rounded-2xl border border-brand-border bg-white p-4" key={booking.id as string}>
      <div className="flex flex-wrap justify-between gap-3"><div><h3 className="font-semibold">{nestedTitle(booking.listings) ?? "Listing request"}</h3><p className="mt-1 text-sm text-muted">{String(booking.request_reference)} · {String(booking.customer_name ?? "Customer")}</p><p className="mt-2 text-sm">{String(booking.customer_phone_number ?? "")}</p></div><Status value={String(booking.booking_status)} /></div>
      <label className="mt-4 grid max-w-sm gap-2 text-sm font-semibold">Update status<select className="rounded-xl border border-brand-border bg-white px-3 py-2" value={booking.booking_status as string} disabled={busy} onChange={(e) => void update(booking.id as string, e.target.value)}>{bookingStatuses.map((status) => <option key={status}>{status}</option>)}</select></label>
    </article>)}</div>
  </Panel>;
}

function Categories({ categories, edit }: { categories: Row[]; edit: (row: Row) => void }) {
  return <Panel title="Categories & listing fields" subtitle="Manage flexible fields without creating new database columns.">
    <div className="grid gap-3">{categories.map((category) => <button className="rounded-2xl border border-brand-border bg-white p-4 text-left hover:border-brand-green" key={category.id as string} onClick={() => edit(category)}><div className="flex justify-between gap-3"><div><h3 className="font-semibold">{category.name as string}</h3><p className="mt-1 text-sm text-muted">{String(category.slug)} · {schema(category).length} fields</p></div><Status value={category.is_active ? "active" : "inactive"} /></div></button>)}</div>
  </Panel>;
}

function Agents({ agents, busy, update }: { agents: Row[]; busy: boolean; update: (id: string, activate: boolean) => void }) {
  return <Panel title="Agents" subtitle="Verify, activate, and deactivate agent access."><div className="grid gap-3">{agents.map((agent) => <article className="rounded-2xl border border-brand-border bg-white p-4" key={agent.id as string}><div className="flex flex-wrap justify-between gap-3"><div><h3 className="font-semibold">{String(agent.display_name ?? agent.business_name ?? "Agent")}</h3><p className="text-sm text-muted">{String(agent.contact_email ?? agent.phone_number ?? "")}</p></div><Status value={`${agent.verification_status} · ${agent.account_status}`} /></div><div className="mt-4 flex gap-2"><button className="btn btn-success" disabled={busy} onClick={() => void update(agent.id as string, true)}>Approve & activate</button><button className="btn btn-outline" disabled={busy} onClick={() => void update(agent.id as string, false)}>Deactivate</button></div></article>)}</div></Panel>;
}

function Users({ users }: { users: Row[] }) {
  return <Panel title="Users" subtitle="Ordinary customer accounts registered in KODIMALI.">
    <div className="grid gap-3">{users.length === 0 ? <Empty text="No registered users yet." /> : users.map((user) =>
      <article className="rounded-2xl border border-brand-border bg-white p-4" key={user.id as string}>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div><h3 className="font-semibold">{String(user.full_name || "KODIMALI user")}</h3>
          <p className="mt-1 text-sm text-muted">{String(user.account_email || "No email")}</p>
          <p className="mt-1 text-sm">{String(user.phone_number || "No phone number")}</p></div>
          <Status value={user.email_confirmed_at ? "email confirmed" : "confirmation pending"} />
        </div>
        <p className="mt-3 text-xs text-muted">Registered {new Date(String(user.created_at)).toLocaleString()} · Language: {String(user.preferred_language || "sw")}</p>
      </article>)}</div>
  </Panel>;
}

function Locations({ rows, busy, add, remove }: { rows: Row[]; busy: boolean; add: (name: string, type: string, parent: string) => Promise<void>; remove: (id: string) => Promise<void> }) {
  const [name, setName] = useState(""); const [type, setType] = useState("region"); const [parent, setParent] = useState("");
  const possibleParents = rows.filter((row) => row.location_type !== "area");
  return <Panel title="Locations" subtitle="Manage the shared region, district, ward, and area hierarchy.">
    <form className="mb-5 grid gap-3 rounded-2xl bg-brand-green-soft p-4 md:grid-cols-[1fr_150px_1fr_auto]" onSubmit={(event) => { event.preventDefault(); void add(name, type, parent).then(() => { setName(""); setParent(""); }); }}>
      <Input label="Location name" value={name} set={setName} required />
      <label className="grid gap-2 font-semibold">Type<select className="rounded-xl border border-brand-border bg-white p-3" value={type} onChange={(event) => { setType(event.target.value); if (event.target.value === "region") setParent(""); }}>{["region", "district", "ward", "area"].map((value) => <option key={value}>{value}</option>)}</select></label>
      <label className="grid gap-2 font-semibold">Parent<select className="rounded-xl border border-brand-border bg-white p-3" value={parent} disabled={type === "region"} onChange={(event) => setParent(event.target.value)}><option value="">{type === "region" ? "No parent" : "Select parent"}</option>{possibleParents.map((row) => <option value={String(row.id)} key={String(row.id)}>{String(row.name)} ({String(row.location_type)})</option>)}</select></label>
      <button className="btn btn-success self-end" disabled={busy || !name.trim() || (type !== "region" && !parent)}>Add</button>
    </form>
    <div className="grid gap-3">{rows.length === 0 ? <Empty text="No locations found." /> : rows.map((row) => <article className="rounded-2xl border border-brand-border bg-white p-4" key={String(row.id)}><div className="flex flex-wrap items-center justify-between gap-3"><div><h3 className="font-semibold">{String(row.name)}</h3><p className="text-sm text-muted">{String(row.location_type)}</p></div><button className="btn btn-outline" disabled={busy} onClick={() => { if (window.confirm(`Delete ${String(row.name)}?`)) void remove(String(row.id)); }}>Delete</button></div></article>)}</div>
  </Panel>;
}

function Reports({ rows, busy, update }: { rows: Row[]; busy: boolean; update: (id: string, status: string) => Promise<void> }) {
  return <Panel title="Reports" subtitle="Review marketplace safety and listing reports."><div className="grid gap-3">{rows.length === 0 ? <Empty text="No reports have been submitted." /> : rows.map((row) => <article className="rounded-2xl border border-brand-border bg-white p-4" key={String(row.id)}><h3 className="font-semibold">{String(row.report_reason)}</h3><p className="mt-1 text-sm text-muted">{String(row.details || "No additional details")}</p><label className="mt-4 grid max-w-xs gap-2 text-sm font-semibold">Status<select className="rounded-xl border border-brand-border bg-white p-3" disabled={busy} value={String(row.status)} onChange={(event) => void update(String(row.id), event.target.value)}>{["open", "in_review", "resolved", "dismissed"].map((value) => <option key={value}>{value}</option>)}</select></label></article>)}</div></Panel>;
}

function Promotions({ rows, busy, toggle }: { rows: Row[]; busy: boolean; toggle: (id: string, active: boolean) => Promise<void> }) {
  return <Panel title="Promotions" subtitle="Control promotions shared by the mobile apps and website."><div className="grid gap-3">{rows.length === 0 ? <Empty text="No promotions available." /> : rows.map((row) => <article className="rounded-2xl border border-brand-border bg-white p-4" key={String(row.id)}><div className="flex flex-wrap items-start justify-between gap-3"><div><h3 className="font-semibold">{String(row.title)}</h3><p className="mt-1 text-sm text-muted">{String(row.description || "")}</p><p className="mt-2 text-xs font-semibold uppercase tracking-wide">{String(row.placement)} · {String(row.visibility_scope)}</p></div><Status value={row.is_active ? "active" : "paused"} /></div><button className="btn btn-outline mt-4" disabled={busy} onClick={() => void toggle(String(row.id), row.is_active !== true)}>{row.is_active ? "Pause promotion" : "Activate promotion"}</button></article>)}</div></Panel>;
}

function Notifications({ rows, markRead }: { rows: Row[]; markRead: (id: string) => Promise<void> }) {
  return <Panel title="Notifications" subtitle="Account and marketplace activity from the shared Supabase notification stream."><div className="grid gap-3">{rows.length === 0 ? <Empty text="No notifications available." /> : rows.map((row) =>
    <article className={`rounded-2xl border p-4 ${row.read_at ? "border-brand-border bg-white" : "border-brand-green bg-brand-green-soft"}`} key={String(row.id)}>
      <div className="flex flex-wrap items-start justify-between gap-3"><div><h3 className="font-semibold">{String(row.title || "Notification")}</h3><p className="mt-1 text-sm">{String(row.body || "")}</p><p className="mt-2 text-xs text-muted">{new Date(String(row.created_at)).toLocaleString()}</p></div>{!row.read_at ? <button className="btn btn-outline" onClick={() => void markRead(String(row.id))}>Mark read</button> : <Status value="read" />}</div>
    </article>)}</div></Panel>;
}

function ProfilePanel({ rows, email }: { rows: Row[]; email: string }) {
  const profile = rows[0] ?? {};
  return <Panel title="Profile" subtitle="The identity attached to this management account."><div className="grid gap-4 sm:grid-cols-2">
    <Info label="Full name" value={String(profile.full_name || "Not provided")} />
    <Info label="Email" value={String(profile.account_email || email)} />
    <Info label="Username" value={String(profile.username || "Not provided")} />
    <Info label="Phone" value={String(profile.phone_number || "Not provided")} />
    <Info label="Language" value={String(profile.preferred_language || "sw")} />
  </div></Panel>;
}

function Info({ label, value }: { label: string; value: string }) {
  return <div className="soft-panel p-4"><p className="text-xs font-bold uppercase tracking-[0.16em] text-muted">{label}</p><p className="mt-2 font-semibold break-words">{value}</p></div>;
}

function AddListingForm({ agentId, onCreated }: { agentId: string; onCreated: () => void }) {
  const supabase = useMemo(() => getBrowserSupabase(), []);
  const [categories, setCategories] = useState<Row[]>([]); const [locations, setLocations] = useState<Row[]>([]);
  const [categoryId, setCategoryId] = useState(""); const [locationId, setLocationId] = useState("");
  const [title, setTitle] = useState(""); const [description, setDescription] = useState(""); const [price, setPrice] = useState("");
  const [period, setPeriod] = useState("month"); const [attributes, setAttributes] = useState<Row>({}); const [busy, setBusy] = useState(false); const [message, setMessage] = useState<string | null>(null);
  useEffect(() => { void Promise.all([
    supabase.from("agent_service_categories").select("asset_categories(id, name, slug, field_schema)").eq("agent_id", agentId),
    supabase.from("locations").select("id, name, location_type").eq("is_active", true).order("name"),
  ]).then(([categoryResult, locationResult]) => {
    if (categoryResult.error) setMessage(categoryResult.error.message); else setCategories((categoryResult.data ?? []).map((row) => relation((row as Row).asset_categories)));
    if (locationResult.error) setMessage(locationResult.error.message); else setLocations((locationResult.data ?? []) as Row[]);
  }); }, [agentId, supabase]);
  const selectedCategory = categories.find((item) => item.id === categoryId); const fields = schema(selectedCategory ?? {});
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setMessage(null);
    const location = locations.find((item) => item.id === locationId);
    const result = await supabase.from("listings").insert({ agent_id: agentId, category_id: categoryId, title: title.trim(), description: description.trim(), location_id: locationId, public_location_label: String(location?.name ?? ""), price_amount: Number(price), price_period: period, listing_attributes: attributes, status: "draft", approval_status: "pending", availability_status: "available" } as never);
    setBusy(false); if (result.error) setMessage(result.error.message); else onCreated();
  }
  return <Panel title="Add asset" subtitle="Create a Supabase listing draft using your assigned categories and dynamic fields."><form className="grid gap-4" onSubmit={submit}>
    <Input label="Title" value={title} set={setTitle} required /><label className="grid gap-2 font-semibold">Description<textarea className="rounded-xl border border-brand-border bg-white p-3" minLength={10} rows={5} value={description} onChange={(event) => setDescription(event.target.value)} required /></label>
    <div className="grid gap-4 sm:grid-cols-2"><label className="grid gap-2 font-semibold">Category<select className="rounded-xl border border-brand-border bg-white p-3" value={categoryId} onChange={(event) => { setCategoryId(event.target.value); setAttributes({}); }} required><option value="">Select category</option>{categories.map((item) => <option value={String(item.id)} key={String(item.id)}>{String(item.name)}</option>)}</select></label><label className="grid gap-2 font-semibold">Location<select className="rounded-xl border border-brand-border bg-white p-3" value={locationId} onChange={(event) => setLocationId(event.target.value)} required><option value="">Select location</option>{locations.map((item) => <option value={String(item.id)} key={String(item.id)}>{String(item.name)} ({String(item.location_type)})</option>)}</select></label></div>
    <div className="grid gap-4 sm:grid-cols-2"><Input label="Price (TZS)" type="number" value={price} set={setPrice} required /><label className="grid gap-2 font-semibold">Price period<select className="rounded-xl border border-brand-border bg-white p-3" value={period} onChange={(event) => setPeriod(event.target.value)}>{["hour", "day", "week", "month", "year"].map((value) => <option key={value}>{value}</option>)}</select></label></div>
    {fields.filter((field) => field.active !== false).map((field) => <DynamicField key={String(field.key)} field={field} value={attributes[String(field.key)]} set={(value) => setAttributes((current) => ({ ...current, [String(field.key)]: value }))} />)}
    {message ? <p className="rounded-xl bg-brand-danger-soft p-3 text-sm text-brand-danger">{message}</p> : null}<button className="btn btn-success" disabled={busy || !categoryId || !locationId}>{busy ? "Creating..." : "Create draft"}</button>
  </form></Panel>;
}

function ListingEditor({ listing, close, save }: { listing: Row; close: () => void; save: (values: Row) => void }) {
  const [title, setTitle] = useState(String(listing.title ?? ""));
  const [description, setDescription] = useState(String(listing.description ?? ""));
  const [price, setPrice] = useState(String(listing.price_amount ?? "0"));
  const [availability, setAvailability] = useState(String(listing.availability_status ?? "available"));
  const fields = schema(listing.asset_categories as Row);
  const initial = (listing.listing_attributes as Row | null) ?? {};
  const [attributes, setAttributes] = useState<Row>(initial);
  return <Modal title="Edit listing" close={close}><form className="grid gap-4" onSubmit={(e) => { e.preventDefault(); save({ title: title.trim(), description: description.trim(), price_amount: Number(price), availability_status: availability, listing_attributes: attributes }); }}>
    <Input label="Title" value={title} set={setTitle} required /><label className="grid gap-2 font-semibold">Description<textarea className="rounded-xl border border-brand-border p-3" rows={4} value={description} onChange={(e) => setDescription(e.target.value)} required /></label><Input label="Price" value={price} set={setPrice} type="number" required />
    <label className="grid gap-2 font-semibold">Availability<select className="rounded-xl border border-brand-border bg-white p-3" value={availability} onChange={(e) => setAvailability(e.target.value)}>{["available", "reserved", "rented", "unavailable"].map((x) => <option key={x}>{x}</option>)}</select></label>
    {fields.filter((field) => field.active !== false).map((field) => <DynamicField key={field.key as string} field={field} value={attributes[field.key as string]} set={(value) => setAttributes((current) => ({ ...current, [field.key as string]: value }))} />)}
    <div className="flex gap-3"><button className="btn btn-success">Save changes</button><button className="btn btn-outline" type="button" onClick={close}>Cancel</button></div>
  </form></Modal>;
}

function CategoryEditor({ category, close, save }: { category: Row; close: () => void; save: (values: Row) => void }) {
  const [fields, setFields] = useState<Row[]>(schema(category));
  const [label, setLabel] = useState("");
  const [type, setType] = useState("text");
  function addField() {
    const key = label.toLowerCase().trim().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
    if (!key || fields.some((field) => field.key === key)) return;
    setFields((current) => [...current, { key, label: label.trim(), type, required: false, active: true, ...(type === "select" ? { options: ["Option 1"] } : {}) }]); setLabel("");
  }
  return <Modal title={`${String(category.name)} listing fields`} close={close}><div className="grid gap-4">
    <div className="grid gap-3 rounded-2xl bg-brand-green-soft p-4 sm:grid-cols-[1fr_150px_auto]"><Input label="New field label" value={label} set={setLabel} /><label className="grid gap-2 font-semibold">Type<select className="rounded-xl border border-brand-border bg-white p-3" value={type} onChange={(e) => setType(e.target.value)}>{["text", "textarea", "number", "boolean", "select"].map((x) => <option key={x}>{x}</option>)}</select></label><button type="button" className="btn btn-success self-end" onClick={addField}>Add field</button></div>
    {fields.map((field, index) => <div className="rounded-2xl border border-brand-border p-4" key={field.key as string}><div className="grid gap-3 sm:grid-cols-2"><Input label="Label" value={String(field.label)} set={(value) => setFields((current) => current.map((item, i) => i === index ? { ...item, label: value } : item))} /><label className="flex items-center gap-2 pt-7 font-semibold"><input type="checkbox" checked={field.required === true} onChange={(e) => setFields((current) => current.map((item, i) => i === index ? { ...item, required: e.target.checked } : item))} />Required</label></div><p className="mt-2 text-xs text-muted">Stable key: {String(field.key)} · {String(field.type)}</p><button className="mt-3 text-sm font-semibold underline" onClick={() => setFields((current) => current.map((item, i) => i === index ? { ...item, active: item.active === false } : item))}>{field.active === false ? "Restore field" : "Retire field"}</button></div>)}
    <div className="flex gap-3"><button className="btn btn-success" onClick={() => save({ field_schema: fields })}>Save fields</button><button className="btn btn-outline" onClick={close}>Cancel</button></div>
  </div></Modal>;
}

function DynamicField({ field, value, set }: { field: Row; value: unknown; set: (value: unknown) => void }) {
  const label = `${String(field.label ?? field.key)}${field.required ? " *" : ""}`;
  if (field.type === "boolean") return <label className="flex items-center gap-3 font-semibold"><input type="checkbox" checked={value === true} onChange={(e) => set(e.target.checked)} />{label}</label>;
  if (field.type === "select") return <label className="grid gap-2 font-semibold">{label}<select className="rounded-xl border border-brand-border bg-white p-3" value={String(value ?? "")} onChange={(e) => set(e.target.value)} required={field.required === true}><option value="">Select</option>{((field.options as unknown[]) ?? []).map((option) => <option key={String(option)}>{String(option)}</option>)}</select></label>;
  return <Input label={label} value={String(value ?? "")} set={(next) => set(field.type === "number" ? Number(next) : next)} type={field.type === "number" ? "number" : "text"} required={field.required === true} />;
}

function Modal({ title, close, children }: { title: string; close: () => void; children: React.ReactNode }) { return <div className="fixed inset-0 z-50 overflow-y-auto bg-brand-navy/60 p-4" role="dialog" aria-modal="true"><div className="mx-auto my-8 max-w-2xl rounded-3xl bg-white p-6 shadow-2xl"><div className="mb-5 flex justify-between gap-4"><h2 className="font-heading text-2xl font-semibold">{title}</h2><button onClick={close} className="text-xl" aria-label="Close">×</button></div>{children}</div></div>; }
function Panel({ title, subtitle, children }: { title: string; subtitle: string; children: React.ReactNode }) { return <div className="surface-card p-5 sm:p-7"><h2 className="font-heading text-3xl font-semibold">{title}</h2><p className="mt-2 mb-6 text-muted">{subtitle}</p>{children}</div>; }
function Input({ label, value, set, type = "text", required = false }: { label: string; value: string; set: (value: string) => void; type?: string; required?: boolean }) { return <label className="grid gap-2 font-semibold">{label}<input className="rounded-xl border border-brand-border bg-white p-3" type={type} value={value} onChange={(e) => set(e.target.value)} required={required} /></label>; }
function Status({ value }: { value: string }) { return <span className="h-fit rounded-full bg-brand-green-soft px-3 py-1 text-xs font-semibold text-brand-navy">{value.replaceAll("_", " ")}</span>; }
function Empty({ text }: { text: string }) { return <p className="rounded-2xl bg-brand-info-soft p-5 text-muted">{text}</p>; }
function schema(row: Row | null | undefined): Row[] { return Array.isArray(row?.field_schema) ? row.field_schema as Row[] : []; }
function relation(value: unknown): Row { if (Array.isArray(value)) return (value[0] as Row | undefined) ?? {}; return value && typeof value === "object" ? value as Row : {}; }
function categoryName(listing: Row) { const value = listing.asset_categories as Row | Row[] | null; const category = Array.isArray(value) ? value[0] : value; return String(category?.name ?? "Listing"); }
function nestedTitle(value: unknown) { const row = Array.isArray(value) ? value[0] : value; return row && typeof row === "object" ? String((row as Row).title ?? "") : null; }
function readError(error: unknown) { if (error && typeof error === "object" && "message" in error) return String(error.message); return "The request could not be completed."; }
function isMissingFunction(error: unknown) { const text = readError(error).toLowerCase(); return text.includes("function") && (text.includes("does not exist") || text.includes("schema cache")); }
async function withRetry<T>(operation: () => PromiseLike<T>, attempts = 2): Promise<T> {
  let lastError: unknown;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      const value = await operation();
      if (value && typeof value === "object" && "error" in value && value.error) {
        throw value.error;
      }
      return value;
    }
    catch (error) {
      lastError = error;
      if (attempt + 1 < attempts) await new Promise((resolve) => setTimeout(resolve, 350));
    }
  }
  throw lastError;
}
