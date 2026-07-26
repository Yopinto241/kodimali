"use client";

import Link from "next/link";
import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { User } from "@supabase/supabase-js";
import { getBrowserSupabase } from "@/lib/supabase-browser";

type Row = Record<string, unknown>;
type Role = "admin" | "agent";
type Tab = "dashboard" | "listings" | "requests" | "categories" | "agents" | "users";

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
        : target === "agents" ? agents.length : users.length;
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
      } else {
        result = await withRetry(() => supabase.rpc("get_admin_customer_users", {
          p_offset: from, p_limit: 20,
        } as never));
      }
      if (result.error) throw result.error;
      const rows = (result.data ?? []) as unknown as Row[];
      if (target === "listings") setListings((old) => append ? [...old, ...rows] : rows);
      if (target === "requests") setBookings((old) => append ? [...old, ...rows] : rows);
      if (target === "categories") setCategories((old) => append ? [...old, ...rows] : rows);
      if (target === "agents") setAgents((old) => append ? [...old, ...rows] : rows);
      if (target === "users") setUsers((old) => append ? [...old, ...rows] : rows);
      loadedTabs.current.add(target);
      setHasMore((old) => ({ ...old, [target]: rows.length === 20 }));
    } catch (error) {
      setMessage(`${readError(error)} Check your connection and retry.`);
    } finally {
      setTabLoading(false);
    }
  }, [agentId, agents.length, bookings.length, categories.length, listings.length, role, supabase, users.length]);

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
    { id: "requests", label: "Requests" },
    ...(role === "admin" ? [
      { id: "categories" as Tab, label: "Categories & fields" },
      { id: "agents" as Tab, label: "Agents" },
    ] : []),
  ];

  return <main className="min-h-screen bg-brand-canvas">
    <header className="border-b border-brand-border bg-white">
      <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-4 px-4 py-5 sm:px-6">
        <div><Link href="/" className="eyebrow">KODIMALI</Link><h1 className="font-heading text-2xl font-semibold">{role === "admin" ? "Admin" : "Agent"} workspace</h1></div>
        <div className="flex items-center gap-3"><span className="hidden text-sm text-muted sm:inline">{user.email}</span>
        <button className="btn btn-outline" onClick={() => void supabase.auth.signOut()}>Sign out</button></div>
      </div>
    </header>
    <div className="mx-auto grid max-w-7xl gap-6 px-4 py-6 sm:px-6 lg:grid-cols-[220px_1fr]">
      <nav className="surface-card grid grid-cols-2 gap-2 p-3 sm:grid-cols-3 lg:flex lg:flex-col" aria-label="Management navigation">
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
  </main>;
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
