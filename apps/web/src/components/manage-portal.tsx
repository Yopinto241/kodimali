"use client";
import { safeUserMessage } from "@/lib/user-message";
import { ListingPublication } from "@/components/listing-publication";
import { uploadListingPhoto } from "@/lib/listing-upload";
import { ListingImagePicker, type ListingPhoto } from "@/components/listing-image-picker";
import { SupervisorLocationChoice } from "@/components/supervisor-territories";
import { PromotionCategorySelect } from "@/components/promotion-category-select";
import { translateUiPrompt } from "@/lib/ui-translation";
import { UiButton, UiText } from "@/components/ui-text";

import Image from "next/image";
import Link from "next/link";
import { useNavigate } from "@/components/navigation-progress";
import {
  FormEvent,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import type { User } from "@supabase/supabase-js";
import { getBrowserSupabase } from "@/lib/supabase-browser";
import { ManageWorkspaceShell } from "@/components/manage-workspace-shell";
import { manageHref, type ManageSection } from "@/lib/manage-routes";
import { NavigationIndicator } from "@/components/navigation-progress";
import { InformationAdminWorkspace } from "@/components/information-admin-workspace";
import { OwnerAgentRecommendations } from "@/components/owner-agent-panel";
import { BusinessOperations } from "@/components/business-operations";
import { AdminAccessPanel } from "@/components/admin-access-panel";

import { ManageListingFilters } from "@/components/manage-listing-filters";
import { LanguageSwitch } from "@/components/language-switch";
import { ManageUsers } from "@/components/manage-users";
import { ManageLocations } from "@/components/manage-locations";
import { SupervisorTeams, SupervisorTerritories, AgentTeamAssignment } from "@/components/supervisor-territories";
import { ManageAddAgent } from "@/components/manage-add-agent";
import { canUseManageTab } from "@/lib/manage-access";

type Row = Record<string, unknown>;
type Role = "admin" | "agent";
type Tab =
  | "events-provider"
  | "events-coordinator"
  | "information"
  | "dashboard"
  | "business"
  | "admin-access"
  | "listings"
  | "add-listing"
  | "requests"
  | "categories"
  | "agents"
  | "owners"
  | "users"
  | "locations"
  | "reports"
  | "promotions"
  | "notifications"
  | "profile";

const bookingStatuses = [
  "new",
  "checking_availability",
  "contacted",
  "viewing_scheduled",
  "reserved",
  "confirmed",
  "completed",
  "cancelled",
  "rejected",
  "no_response",
  "agent_delayed",
];

export function ManagePortal({ preferredRole, requestedSection = "dashboard", recordId }: { preferredRole?: Role; requestedSection?: ManageSection; recordId?: string }) {
  const navigate = useNavigate();
  const routeParams = typeof window === "undefined" ? new URLSearchParams() : new URLSearchParams(window.location.search);
  const listingSearch = routeParams.get("q") ?? "";
  const listingStatus = routeParams.get("status") ?? "";
  const listingReview = routeParams.get("review") ?? "";
  const listingCategory = routeParams.get("category") ?? "";
  const listingPage = Math.max(0, Number(routeParams.get("page")) || 0);
  const supabase = useMemo(() => getBrowserSupabase(), []);
  const [user, setUser] = useState<User | null>(null);
  const [availableRoles, setAvailableRoles] = useState<string[]>([]);
  const [role, setRole] = useState<Role | null>(null);
  const [permissions, setPermissions] = useState<string[]>([]);
  const [agentId, setAgentId] = useState<string | null>(null);
  const [tab, setTab] = useState<Tab>(requestedSection);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [listings, setListings] = useState<Row[]>([]);
  const [bookings, setBookings] = useState<Row[]>([]);
  const [categories, setCategories] = useState<Row[]>([]);
  const [agents, setAgents] = useState<Row[]>([]);
  const [extraRows, setExtraRows] = useState<Partial<Record<Tab, Row[]>>>({});
  const [counts, setCounts] = useState<Row>({});
  const [tabLoading, setTabLoading] = useState(false);
  const [tabError, setTabError] = useState(false);
  const [online, setOnline] = useState(true);
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
        supabase
          .from("booking_requests")
          .select("id", { count: "exact", head: true }),
        supabase.from("agents").select("id", { count: "exact", head: true }),
      ]);
      setCounts({
        listings: listingResult.count ?? 0,
        requests: bookingResult.count ?? 0,
        agents: agentResult.count ?? 0,
      });
    }
  }, [supabase]);

  const loadWorkspace = useCallback(
    async (nextUser: User) => {
      setLoading(true);
      setRole(null);
      setPermissions([]);
      setMessage(null);
      try {
        const { data: roleRows, error: roleError } = await supabase
          .from("user_roles")
          .select("role")
          .eq("profile_id", nextUser.id);
        if (roleError) throw roleError;
        const roles = ((roleRows ?? []) as unknown as { role: string }[]).map(
          (item) => item.role,
        );
        setAvailableRoles(roles);
        const nextRole: Role | null = preferredRole
          ? roles.includes(preferredRole) ? preferredRole : null
          : requestedSection === "add-listing" && roles.includes("agent") ? "agent" : roles.includes("admin") ? "admin" : roles.includes("agent") ? "agent" : null;
        if (!nextRole && roles.includes("owner")) {
          navigate("/owner");
          return;
        }
        let nextPermissions: string[] = [];
        if (nextRole === "admin") {
          const result = await supabase.rpc("get_my_admin_permissions");
          if (result.error) throw result.error;
          if (!Array.isArray(result.data)) throw new Error("Could not load administrative permissions.");
          nextPermissions = result.data as string[];
        }
        setPermissions(nextPermissions);
        setRole(nextRole);
        if (!nextRole) {
          setMessage("This account does not have approved Manage access.");
          setLoading(false);
          return;
        }

        let nextAgentId: string | null = null;
        if (nextRole === "agent") {
          const { data: agent, error } = await supabase
            .from("agents")
            .select("id")
            .eq("profile_id", nextUser.id)
            .maybeSingle();
          if (error) throw error;
          nextAgentId =
            (agent as unknown as { id?: string } | null)?.id ?? null;
        }
        setAgentId(nextAgentId);
        loadedTabs.current.clear();
        setLoading(false);
        const firstTab = (["dashboard", "information", "business", "requests", "listings", "agents", "owners", "users", "profile"] as Tab[])
          .find((candidate) => canUseManageTab(nextRole, nextPermissions, candidate)) ?? "profile";
        if (canUseManageTab(nextRole, nextPermissions, requestedSection)) setTab(requestedSection);
        else if (requestedSection === "dashboard") { navigate(manageHref(firstTab, nextRole)); return; }
        else setTab(requestedSection);
        if (canUseManageTab(nextRole, nextPermissions, "dashboard")) void loadDashboardCounts();
      } catch (error) {
        setMessage(readError(error));
      } finally {
        setLoading(false);
      }
    },
    [loadDashboardCounts, supabase, preferredRole, requestedSection, navigate],
  );

  const loadTabData = useCallback(
    async (target: Tab, append = false) => {
      if (
        target === "users" ||
        target === "locations" ||
        target === "information" ||
        target === "dashboard" ||
        target === "business" ||
        target === "admin-access" ||
        !role || !canUseManageTab(role, permissions, target)
      )
        return;
      if (!append && loadedTabs.current.has(target)) return;
      setTabLoading(true);
      setTabError(false);
      setMessage(null);
      try {
        const currentLength =
          target === "listings"
            ? listings.length
            : target === "requests"
              ? bookings.length
              : target === "categories"
                ? categories.length
                : target === "agents"
                  ? agents.length
                  : (extraRows[target]?.length ?? 0);
        const from = target === "listings" && !recordId ? listingPage * 20 : append ? currentLength : 0;
        const to = from + 19;
        let result;
        if (target === "listings") {
          let query = supabase
            .from("listings")
            .select(
              "id, agent_id, owner_id, owners(full_name,phone_number,notes), title, description, price_amount, price_period, deposit_required_amount, listing_rules, public_location_label, status, publication_review_status, availability_status, removed_reason, removed_from_market_at, listing_attributes, created_at, listing_media(id,storage_path,media_type,display_order), asset_categories(id, name, slug, field_schema)",
            )
            .order("created_at", { ascending: false })
            .range(from, to);
          if (role === "agent" && agentId)
            query = query.eq("agent_id", agentId);
          if (role === "agent" && !agentId) { setListings([]); return; }
          if (recordId) query = query.eq("id", recordId);
          else {
            if (listingSearch.trim()) query = query.ilike("title", `%${listingSearch.trim().replace(/[%_]/g, "")}%`);
            if (listingReview) query = query.eq("publication_review_status", listingReview);
            if (listingStatus) query = query.eq("status", listingStatus);
            if (listingCategory) query = query.eq("category_id", listingCategory);
          }
          result = await withRetry(() => query.order("display_order", { referencedTable: "listing_media" }).limit(recordId ? 20 : 1, { referencedTable: "listing_media" }));
          if (!result.error && result.data) {
            const paths = (result.data as Row[]).flatMap(row => ((row.listing_media ?? []) as Row[]).map(media => String(media.storage_path)));
            if (paths.length) {
              const signed = await supabase.storage.from("listing-media").createSignedUrls(paths, 3600);
              const urls = new Map((signed.data ?? []).map(media => [media.path, media.signedUrl]));
              for (const row of result.data as Row[]) for (const media of (row.listing_media ?? []) as Row[]) media.media_url = urls.get(String(media.storage_path)) ?? "";
            }
          }
        } else if (target === "requests") {
          let query = supabase
            .from("booking_requests")
            .select(
              "id, agent_id, request_reference, customer_name, customer_phone_number, requested_start_at, requested_end_at, request_message, booking_status, created_at, listings(title)",
            )
            .order("created_at", { ascending: false })
            .range(from, to);
          if (role === "agent" && agentId)
            query = query.eq("agent_id", agentId);
          result = await withRetry(() => query);
        } else if (target === "categories") {
          result = await withRetry(() =>
            supabase
              .from("asset_categories")
              .select(
                "id, name, slug, description, display_order, is_active, home_feed_weight, field_schema",
              )
              .order("display_order")
              .range(from, to),
          );
        } else if (target === "agents") {
          result = await withRetry(() =>
            supabase
              .from("agents")
              .select(
                "id, profile_id, display_name, business_name, phone_number, contact_email, verification_status, account_status, created_at, supervisor_id",
              )
              .order("created_at", { ascending: false })
              .range(from, to),
          );
        } else if (target === "owners") {
          const [applications, claims] = await Promise.all([
            withRetry(() =>
              supabase
                .from("owner_applications")
                .select(
                  "id, applicant_id, owner_type, legal_name, phone_number, authorization_summary, status, review_notes, created_at",
                )
                .order("created_at", { ascending: false })
                .range(from, to),
            ),
            withRetry(() =>
              supabase
                .from("owner_asset_claims")
                .select(
                  "id, authority_type, status, notes, created_at, owner_profiles(display_name,verification_status), rental_assets(display_name,category,verification_status)",
                )
                .order("created_at", { ascending: false })
                .range(from, to),
            ),
          ]);
          result = {
            data: [
              ...((applications.data ?? []) as Row[]).map((row) => ({
                ...row,
                record_type: "application",
              })),
              ...((claims.data ?? []) as Row[]).map((row) => ({
                ...row,
                record_type: "asset_claim",
              })),
            ],
            error: applications.error ?? claims.error,
          };
        } else if (target === "reports") {
          result = await withRetry(() =>
            supabase
              .from("reports")
              .select(
                "id, listing_id, report_reason, details, status, created_at",
              )
              .order("created_at", { ascending: false })
              .range(from, to),
          );
        } else if (target === "promotions") {
          result = await withRetry(() =>
            supabase
              .from("platform_promotions")
              .select(
                "id, title, description, placement, visibility_scope, is_active, start_at, end_at, created_at, target_category_ids",
              )
              .order("created_at", { ascending: false })
              .range(from, to),
          );
        } else if (target === "notifications") {
          result = await withRetry(() =>
            supabase
              .from("notifications")
              .select("id, title, body, type, read_at, created_at")
              .eq("user_id", user!.id)
              .order("created_at", { ascending: false })
              .range(from, to),
          );
        } else if (target === "profile") {
          result = await withRetry(() =>
            supabase
              .from("profiles")
              .select(
                "id, full_name, username, account_email, phone_number, preferred_language, created_at",
              )
              .eq("id", user!.id)
              .limit(1),
          );
        } else {
          return;
        }
        if (result.error) throw result.error;
        const rows = (result.data ?? []) as unknown as Row[];
        if (target === "listings")
          setListings((old) => (append ? [...old, ...rows] : rows));
        if (target === "requests")
          setBookings((old) => (append ? [...old, ...rows] : rows));
        if (target === "categories")
          setCategories((old) => (append ? [...old, ...rows] : rows));
        if (target === "agents")
          setAgents((old) => (append ? [...old, ...rows] : rows));
        if (
          !["listings", "requests", "categories", "agents", "users"].includes(
            target,
          )
        ) {
          setExtraRows((old) => ({
            ...old,
            [target]: append ? [...(old[target] ?? []), ...rows] : rows,
          }));
        }
        loadedTabs.current.add(target);
        setHasMore((old) => ({ ...old, [target]: rows.length === 20 }));
      } catch (error) {
        setTabError(true);
        setMessage(`${readError(error)} Check your connection and retry.`);
      } finally {
        setTabLoading(false);
      }
    },
    [
      recordId, listingSearch, listingStatus, listingReview, listingCategory, listingPage,
      agentId,
      agents.length,
      bookings.length,
      categories.length,
      extraRows,
      listings.length,
      role,
      permissions,
      supabase,
      user,
    ],
  );

  useEffect(() => {
    const applyUser = (nextUser: User | null) => {
      setUser(nextUser);
      if (nextUser && activeUserId.current !== nextUser.id) {
        activeUserId.current = nextUser.id;
        void loadWorkspace(nextUser);
      } else {
        if (!nextUser) {
          activeUserId.current = null;
          setRole(null);
          setPermissions([]);
          setAvailableRoles([]);
          loadedTabs.current.clear();
          setListings([]); setBookings([]); setAgents([]); setExtraRows({}); setCounts({});
          setLoading(false);
        }
      }
    };
    // getSession reads the locally persisted session immediately. Every data
    // query is still authorized by Supabase RLS, so page startup need not wait
    // for a separate remote getUser round trip.
    void supabase.auth
      .getSession()
      .then(({ data }) => applyUser(data.session?.user ?? null));
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      applyUser(session?.user ?? null);
    });
    return () => data.subscription.unsubscribe();
  }, [loadWorkspace, supabase]);

  useEffect(() => {
    const updateConnection = () => setOnline(navigator.onLine);
    const timer = window.setTimeout(updateConnection, 0);
    window.addEventListener("online", updateConnection);
    window.addEventListener("offline", updateConnection);
    return () => {
      window.clearTimeout(timer);
      window.removeEventListener("online", updateConnection);
      window.removeEventListener("offline", updateConnection);
    };
  }, []);

  useEffect(() => {
    if (!role || loading) return;
    const task = window.setTimeout(() => { void loadTabData(tab); }, 0);
    return () => window.clearTimeout(task);
  }, [tab, role, loading, loadTabData]);

  async function signIn(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setMessage(null);
    const { error } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password,
    });
    if (error) setMessage(safeUserMessage(error));
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

  async function moderateListing(
    listingId: string,
    status: "active" | "inactive",
  ) {
    await perform(async () => {
      const { error } = await supabase.functions.invoke("approve-listing", {
        body: { listingId, status, availabilityStatus: "available" },
      });
      if (error) throw error;
      await refresh();
    }, `Listing changed to ${status}.`);
  }

  async function deleteListingPermanently(listing: Row) {
    const title = String(listing.title ?? "this listing");
    const confirmation = window.prompt(translateUiPrompt(`Permanently delete “${title}”? This removes its media and related activity and cannot be undone. Type DELETE to continue.`),
    );
    if (confirmation !== "DELETE") {
      setMessage("Permanent deletion cancelled.");
      return;
    }
    await perform(async () => {
      const { error } = await supabase.functions.invoke(
        "admin-delete-listing",
        {
          body: { listingId: listing.id, confirm_delete_with_inquiries: true },
        },
      );
      if (error) throw error;
      setListings((current) =>
        current.filter((item) => item.id !== listing.id),
      );
      loadedTabs.current.delete("listings");
    }, "Listing and related media were permanently deleted.");
  }

  async function updateBooking(bookingId: string, status: string) {
    await perform(async () => {
      const rpcResult = await supabase.rpc("manage_update_booking_status", {
        p_booking_id: bookingId,
        p_status: status,
      } as never);
      if (rpcResult.error) {
        if (!isMissingFunction(rpcResult.error)) throw rpcResult.error;
        const fallback = await supabase
          .from("booking_requests")
          .update({ booking_status: status } as never)
          .eq("id", bookingId);
        if (fallback.error) throw fallback.error;
      }
      setBookings((current) =>
        current.map((item) =>
          item.id === bookingId ? { ...item, booking_status: status } : item,
        ),
      );
    }, "Request status updated.");
  }

  async function updateAgent(id: string, activate: boolean) {
    await perform(
      async () => {
        const { error } = await supabase.functions.invoke("verify-agent", {
          body: {
            agentId: id,
            accountStatus: activate ? "active" : "deactivated",
            verificationStatus: activate ? "approved" : "rejected",
          },
        });
        if (error) throw error;
        await refresh();
      },
      activate ? "Agent approved and activated." : "Agent deactivated.",
    );
  }

  async function reviewOwner(id: string, approve: boolean) {
    await perform(
      async () => {
        const result = await supabase.rpc("review_owner_application", {
          p_application_id: id,
          p_approve: approve,
          p_notes: null,
        } as never);
        if (result.error) throw result.error;
        loadedTabs.current.delete("owners");
        await loadTabData("owners");
      },
      approve
        ? "Owner verified and workspace enabled."
        : "Owner application rejected.",
    );
  }

  async function reviewOwnerAsset(id: string, approve: boolean) {
    await perform(
      async () => {
        const result = await supabase.rpc("review_owner_asset_claim", {
          p_claim_id: id,
          p_approve: approve,
          p_notes: null,
        } as never);
        if (result.error) throw result.error;
        loadedTabs.current.delete("owners");
        await loadTabData("owners");
      },
      approve
        ? "Owner/manager authority and item verified for booking."
        : "Asset claim rejected.",
    );
  }

  async function updateReport(id: string, status: string) {
    await perform(async () => {
      const result = await supabase
        .from("reports")
        .update({ status } as never)
        .eq("id", id);
      if (result.error) throw result.error;
      loadedTabs.current.delete("reports");
      await loadTabData("reports");
    }, "Report status updated.");
  }

  async function togglePromotion(id: string, active: boolean) {
    await perform(
      async () => {
        const result = await supabase
          .from("platform_promotions")
          .update({ is_active: active } as never)
          .eq("id", id);
        if (result.error) throw result.error;
        loadedTabs.current.delete("promotions");
        await loadTabData("promotions");
      },
      active ? "Promotion activated." : "Promotion paused.",
    );
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
  if (!user)
    return (
      <ManageLogin
        email={email}
        password={password}
        busy={busy}
        message={message}
        setEmail={setEmail}
        setPassword={setPassword}
        submit={signIn}
      />
    );

  if (!role) {
    return (
      <main className="mx-auto max-w-3xl px-4 py-16">
        <div className="surface-card p-8">
          <h1 className="font-heading text-3xl font-semibold"><UiText text={"Access unavailable"} /></h1>
          <p className="mt-3 text-muted"><UiText text={message} /></p>
          <button className="btn btn-primary mt-6 mr-3" onClick={() => void loadWorkspace(user)}><UiText text={"Retry access"} /></button>
          <button
            className="btn btn-outline mt-6"
            onClick={() => void supabase.auth.signOut()}
          ><UiText text={"Sign out"} /></button>
        </div>
      </main>
    );
  }

  const tabs = ([
    { id: "dashboard", label: "Dashboard" },
    { id: "information", label: "Information Administration" },
    {
      id: "business",
      label: role === "admin" ? "Business operations" : "Business centre",
    },
    ...(role === "admin"
      ? [
          { id: "users" as Tab, label: "Users" },
          { id: "admin-access" as Tab, label: "Admin access" },
        ]
      : []),
    { id: "listings", label: "Listings" },
    ...(role === "agent"
      ? [{ id: "add-listing" as Tab, label: "Add asset" }]
      : []),
    { id: "requests", label: "Requests" },
    ...(role === "admin"
      ? [
          { id: "categories" as Tab, label: "Categories & fields" },
          { id: "agents" as Tab, label: "Agents" },
          { id: "owners" as Tab, label: "Owners" },
          { id: "locations" as Tab, label: "Locations" },
          { id: "reports" as Tab, label: "Reports" },
          { id: "promotions" as Tab, label: "Promotions" },
        ]
      : []),
    { id: "events-provider", label: "Events provider" },
    { id: "events-coordinator", label: "Events coordinator" },
    { id: "notifications", label: "Notifications" },
    { id: "profile", label: "Profile" },
  ] satisfies { id: Tab; label: string }[]).filter((item) => canUseManageTab(role, permissions, item.id));

  return (
    <ManageWorkspaceShell availableRoles={availableRoles} section={tab} role={role} tabs={tabs} signOut={() => void supabase.auth.signOut()}>
      {!canUseManageTab(role, permissions, tab) ? <div role="alert" className="surface-card p-6"><UiText text="Access unavailable" /></div> : <>
          {!online ? (
            <p className="mb-4 rounded-2xl bg-brand-amber-soft p-4 text-sm font-semibold text-brand-navy"><UiText text={"You are offline. Existing information remains visible; reconnect before saving changes."} /></p>
          ) : null}
          {message ? (
            <p
              className="mb-4 rounded-2xl bg-brand-info-soft p-4 text-sm text-brand-navy"
              role="status"
            >
              <UiText text={message} />
              {tabError && <button className="btn btn-outline ml-2" onClick={() => {loadedTabs.current.delete(tab); void loadTabData(tab);}}><UiText text="Retry" /></button>}
            </p>
          ) : null}
          {tab === "information" ? <InformationAdminWorkspace /> : null}
          {tab === "agents" && role === "admin" && !permissions.includes("supervisor.scoped") ? <OwnerAgentRecommendations /> : null}
          {tab === "dashboard" ? (
            <Dashboard role={role} counts={counts} />
          ) : null}
          {tab === "business" ? (
            <BusinessOperations role={role} agentId={agentId} permissions={permissions} />
          ) : null}
          {tab === "admin-access" && role === "admin" ? (
            <AdminAccessPanel />
          ) : null}
          {tabLoading ? (
            <NavigationIndicator inline />
          ) : null}
          {tab === "listings" && !tabLoading && !tabError ? (
            <><ManageListingFilters role={role} hasMore={Boolean(hasMore.listings) && !tabLoading} detail={Boolean(recordId)} /><Listings
              detail={Boolean(recordId)}
              role={role}
              listings={listings}
              busy={busy}
              edit={setEditingListing}
              moderate={moderateListing}
              removePermanently={deleteListingPermanently}
            /></>
          ) : null}
          {tab === "requests" ? (
            <Requests bookings={bookings} busy={busy} update={updateBooking} />
          ) : null}
          {tab === "categories" && role === "admin" ? (
            <Categories categories={categories} edit={setEditingCategory} />
          ) : null}
          {tab === "agents" && role === "admin" ? (
            <Agents agents={agents} busy={busy} update={updateAgent} onCreated={() => void refresh()} canAssign={permissions.includes("*")} scoped={permissions.includes("supervisor.scoped")} />
          ) : null}
          {tab === "owners" && role === "admin" ? (
            <Owners
              rows={extraRows.owners ?? []}
              busy={busy}
              review={reviewOwner}
              reviewAsset={reviewOwnerAsset}
            />
          ) : null}
          {tab === "users" && role === "admin" ? <ManageUsers recordId={recordId} /> : null}
          {tab === "locations" && role === "admin" ? (
            <ManageLocations />
          ) : null}
          {tab === "reports" && role === "admin" ? (
            <Reports
              rows={extraRows.reports ?? []}
              busy={busy}
              update={updateReport}
            />
          ) : null}
          {tab === "promotions" && role === "admin" ? (
            <Promotions
              rows={extraRows.promotions ?? []}
              busy={busy}
              toggle={togglePromotion}
            />
          ) : null}
          {tab === "notifications" ? (
            <Notifications
              rows={extraRows.notifications ?? []}
              markRead={async (id) => {
                await supabase
                  .from("notifications")
                  .update({ read_at: new Date().toISOString() } as never)
                  .eq("id", id);
                loadedTabs.current.delete("notifications");
                await loadTabData("notifications");
              }}
            />
          ) : null}
          {tab === "profile" ? (
            <ProfilePanel
              rows={extraRows.profile ?? []}
              email={user.email ?? ""}
            />
          ) : null}
          {tab === "add-listing" && role === "agent" && agentId ? (
            <AddListingForm agentId={agentId} />
          ) : null}
          {!["dashboard", "listings", "users", "locations"].includes(tab) && hasMore[tab] ? (
            <button
              className="btn btn-outline mt-4"
              disabled={tabLoading}
              onClick={() => void loadTabData(tab, true)}
            >
              <UiText text={tabLoading ? "Loading..." : "Load 20 more"} />
            </button>
          ) : null}
      </>}
      {editingListing ? (
        <ListingEditor
          listing={editingListing}
          close={() => setEditingListing(null)}
          save={(values) =>
            perform(async () => {
              const result = await supabase.rpc("manage_save_listing_with_owner", { p_listing_id: editingListing.id, p_values: values } as never);
              if (result.error) throw result.error;
              setEditingListing(null);
              await refresh();
            }, "Listing saved.")
          }
        />
      ) : null}
      {editingCategory ? (
        <CategoryEditor
          category={editingCategory}
          close={() => setEditingCategory(null)}
          save={(values) =>
            perform(async () => {
              const rpcResult = await supabase.rpc(
                "manage_save_category_fields",
                {
                  p_category_id: editingCategory.id,
                  p_field_schema: values.field_schema,
                } as never,
              );
              if (rpcResult.error) {
                if (!isMissingFunction(rpcResult.error)) throw rpcResult.error;
                const fallback = await supabase
                  .from("asset_categories")
                  .update(values as never)
                  .eq("id", editingCategory.id as string);
                if (fallback.error) throw fallback.error;
              }
              setEditingCategory(null);
              await refresh();
            }, "Category fields saved.")
          }
        />
      ) : null}
    </ManageWorkspaceShell>
  );
}

function ManageLoading() {
  return (
    <NavigationIndicator />
  );
}

function ManageLogin(props: {
  email: string;
  password: string;
  busy: boolean;
  message: string | null;
  setEmail: (v: string) => void;
  setPassword: (v: string) => void;
  submit: (e: FormEvent<HTMLFormElement>) => void;
}) {
  return (
    <main className="mx-auto grid min-h-[80vh] max-w-6xl items-center gap-10 px-4 py-12 lg:grid-cols-2">
      <div>
        <p className="eyebrow">KODIMALI Manage</p>
        <h1 className="mt-3 font-heading text-5xl font-semibold text-brand-ink"><UiText text={"One secure entrance for the business side."} /></h1>
        <p className="mt-5 max-w-xl text-lg text-muted"><UiText text={"Agents, hall owners, authorized managers and administrators use their approved KODIMALI credentials here. Your verified role opens the correct workspace automatically."} /></p>
        <div className="mt-6 flex flex-wrap gap-3">
          <Link prefetch={false} href="/manage/register/agent" className="btn btn-success"><UiText text={"Register as agent"} /></Link>
          <Link
            href="/manage/register/agent?category=ceremony-hall"
            className="btn btn-outline"
          ><UiText text={"Register as hall agent"} /></Link>
          <Link prefetch={false} href="/manage/register/owner" className="btn btn-outline"><UiText text={"Register as owner"} /></Link>
          <Link
            href="/manage/register/owner?type=authorized_manager"
            className="btn btn-outline"
          ><UiText text={"Register as hall manager"} /></Link>
        </div>
        <p className="mt-4 text-sm text-muted"><UiText text={"Administrator accounts are created or approved internally."} /></p>
      </div>
      <form
        className="manage-login-form surface-card grid gap-4 p-6 sm:p-8"
        onSubmit={props.submit}
      >
        <div className="flex flex-wrap items-center justify-between gap-3"><h2 className="font-heading text-2xl font-semibold"><UiText text={"Manage sign in"} /></h2><LanguageSwitch /></div>
        <label className="grid gap-2 font-semibold"><UiText text={"Email"} /><input
            className="rounded-2xl border border-brand-border bg-white px-4 py-3"
            type="email"
            value={props.email}
            onChange={(e) => props.setEmail(e.target.value)}
            required
          />
        </label>
        <label className="grid gap-2 font-semibold"><UiText text={"Password"} /><input
            className="rounded-2xl border border-brand-border bg-white px-4 py-3"
            type="password"
            minLength={6}
            value={props.password}
            onChange={(e) => props.setPassword(e.target.value)}
            required
          />
        </label>
        <button className="btn btn-success" disabled={props.busy}>
          <UiText text={props.busy ? "Signing in..." : "Sign in"} />
        </button>
        {props.message ? (
          <p className="manage-login-feedback" role="alert">
            <UiText text={props.message} />
          </p>
        ) : null}
        <div className="grid gap-2 text-center text-sm font-semibold">
          <Link prefetch={false} href="/" className="underline"><UiText text={"Return to marketplace"} /></Link>
          <Link prefetch={false} href="/login" className="underline"><UiText text={"Customer login"} /></Link>
        </div>
      </form>
    </main>
  );
}

function Dashboard({ role, counts }: { role: Role; counts: Row }) {
  const cards = [
    ["Listings", Number(counts.listings ?? 0)],
    ["Active listings", Number(counts.active_listings ?? 0)],
    ["Open requests", Number(counts.open_requests ?? counts.requests ?? 0)],
    ...(role === "admin" ? [["Agents", Number(counts.agents ?? 0)]] : []),
  ];
  return (
    <>
      <div className="surface-card p-6 sm:p-8">
        <p className="eyebrow"><UiText text={"Live overview"} /></p>
        <h2 className="mt-2 font-heading text-3xl font-semibold"><UiText text={"Marketplace operations"} /></h2>
        <p className="mt-2 text-muted"><UiText text={"Review listings, customer requests and marketplace activity."} /></p>
      </div>
      <div className="mt-5 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {cards.map(([label, value]) => (
          <article className="soft-panel p-5" key={String(label)}>
            <p className="text-sm font-semibold text-muted"><UiText text={label} /></p>
            <p className="mt-2 font-heading text-4xl font-semibold">{value}</p>
          </article>
        ))}
      </div>
    </>
  );
}

function Listings({
  detail,
  role,
  listings,
  busy,
  edit,
  moderate,
  removePermanently,
}: {
  detail?: boolean;
  role: Role;
  listings: Row[];
  busy: boolean;
  edit: (row: Row) => void;
  moderate: (id: string, status: "active" | "inactive") => void;
  removePermanently: (row: Row) => void;
}) {
  return (
    <Panel
      title="Listings"
      subtitle={
        role === "admin"
          ? "Review and control marketplace visibility."
          : "Edit your public listing information and availability."
      }
    >
      <div className="grid gap-3">
        {listings.length === 0 ? (
          <Empty text="No listings available." />
        ) : (
          listings.map((listing) => (
            <article
              className="rounded-2xl border border-brand-border bg-white p-4"
              key={listing.id as string}
            >
              {!detail && ((listing.listing_media ?? []) as Row[]).some(media => media.media_type === "image" && media.media_url) && <Image unoptimized width={640} height={360} src={String(((listing.listing_media ?? []) as Row[])[0]?.media_url ?? "")} alt={String(listing.title)} className="mb-3 aspect-video max-h-48 w-full rounded-xl object-cover" />}
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <h3 className="font-semibold">{detail ? String(listing.title) : <Link prefetch={false} className="underline" href={`/manage/listings/${listing.id}?${typeof window === "undefined" ? "" : new URLSearchParams(window.location.search)}`}>{String(listing.title)}</Link>}</h3>
                  <p className="mt-1 text-sm text-muted">
                    {categoryName(listing)} ·{" "}
                    {String(listing.public_location_label ?? "")}
                  </p>
                </div>
                <div className="flex flex-wrap gap-2"><Status value={String(listing.status)} /><Status value={String(listing.publication_review_status ?? "pending")} /></div>
              </div>
              <p className="mt-3 font-bold">TZS {Number(listing.price_amount ?? 0).toLocaleString()} / <UiText text={String(listing.price_period ?? "")} /></p>
              {detail && <div className="mt-4 grid gap-3"><p className="whitespace-pre-wrap">{String(listing.description ?? "")}</p><p><UiText text="Availability" />: <UiText text={String(listing.availability_status ?? "")} /></p><div className="grid grid-cols-2 gap-3">{((listing.listing_media ?? []) as Row[]).filter(media => media.media_type === "image" && media.media_url).map(media => <Image unoptimized width={640} height={360} key={String(media.id)} src={String(media.media_url)} alt={String(listing.title)} className="aspect-video w-full rounded-xl object-cover" />)}</div></div>}
              {detail && role === "agent" && ["draft", "inactive"].includes(String(listing.status)) && !listing.removed_reason && !listing.removed_from_market_at && <ListingPublication listingId={String(listing.id)} />}
              <div className="mt-4 flex flex-wrap gap-2">
                <button
                  className="btn btn-outline"
                  onClick={() => edit(listing)}
                ><UiText text={"Edit"} /></button>
                {role === "admin" ? (
                  <>
                    <button
                      className="btn btn-success"
                      disabled={busy}
                      onClick={() =>
                        void moderate(listing.id as string, "active")
                      }
                    ><UiText text={"Approve / activate"} /></button>
                    <button
                      className="btn btn-outline"
                      disabled={busy}
                      onClick={() =>
                        void moderate(listing.id as string, "inactive")
                      }
                    ><UiText text={"Remove"} /></button>
                    <button
                      className="rounded-full border border-red-300 bg-red-50 px-4 py-2 text-sm font-bold text-red-700 transition hover:bg-red-100 disabled:opacity-50"
                      disabled={busy}
                      onClick={() => void removePermanently(listing)}
                    ><UiText text={"Delete permanently"} /></button>
                  </>
                ) : null}
              </div>
            </article>
          ))
        )}
      </div>
    </Panel>
  );
}

function Requests({
  bookings,
  busy,
  update,
}: {
  bookings: Row[];
  busy: boolean;
  update: (id: string, status: string) => void;
}) {
  return (
    <Panel
      title="Customer requests"
      subtitle="Track inquiries and keep each customer informed with current status."
    >
      <div className="grid gap-3">
        {bookings.length === 0 ? (
          <Empty text="No customer requests yet." />
        ) : (
          bookings.map((booking) => (
            <article
              className="rounded-2xl border border-brand-border bg-white p-4"
              key={booking.id as string}
            >
              <div className="flex flex-wrap justify-between gap-3">
                <div>
                  <h3 className="font-semibold">
                    {nestedTitle(booking.listings) ?? "Listing request"}
                  </h3>
                  <p className="mt-1 text-sm text-muted">
                    {String(booking.request_reference)} ·{" "}
                    {String(booking.customer_name ?? "Customer")}
                  </p>
                  <p className="mt-2 text-sm">
                    {String(booking.customer_phone_number ?? "")}
                  </p>
                </div>
                <Status value={String(booking.booking_status)} />
              </div>
              <label className="mt-4 grid max-w-sm gap-2 text-sm font-semibold"><UiText text={"Update status"} /><select
                  className="rounded-xl border border-brand-border bg-white px-3 py-2"
                  value={booking.booking_status as string}
                  disabled={busy}
                  onChange={(e) =>
                    void update(booking.id as string, e.target.value)
                  }
                >
                  {bookingStatuses.map((status) => (
                    <option key={status}>{status}</option>
                  ))}
                </select>
              </label>
            </article>
          ))
        )}
      </div>
    </Panel>
  );
}

function Categories({
  categories,
  edit,
}: {
  categories: Row[];
  edit: (row: Row) => void;
}) {
  return (
    <Panel
      title="Categories & listing fields"
      subtitle="Manage flexible fields without creating new database columns."
    >
      <div className="grid gap-3">
        {categories.map((category) => (
          <button
            className="rounded-2xl border border-brand-border bg-white p-4 text-left hover:border-brand-green"
            key={category.id as string}
            onClick={() => edit(category)}
          >
            <div className="flex justify-between gap-3">
              <div>
                <h3 className="font-semibold">{category.name as string}</h3>
                <p className="mt-1 text-sm text-muted">
                  {String(category.slug)} · {schema(category).length}<UiText text={" fields"} /></p>
              </div>
              <Status value={category.is_active ? "active" : "inactive"} />
            </div>
          </button>
        ))}
      </div>
    </Panel>
  );
}

function Agents({
  agents,
  busy,
  update,
  onCreated,
  canAssign,
  scoped,
}: {
  agents: Row[];
  busy: boolean;
  update: (id: string, activate: boolean) => void;
  onCreated: () => void;
  canAssign: boolean;
  scoped: boolean;
}) {
  return (
    <SupervisorTeams enabled={canAssign}><Panel
      title="Agents"
      subtitle="Verify, activate, and deactivate agent access."
    >
      <ManageAddAgent onCreated={onCreated} scoped={scoped} />
      {canAssign && <SupervisorTerritories />}
      <div className="grid gap-3">
        {agents.map((agent) => (
          <article
            className="rounded-2xl border border-brand-border bg-white p-4"
            key={agent.id as string}
          >
            <div className="flex flex-wrap justify-between gap-3">
              <div>
                <h3 className="font-semibold">
                  {String(agent.display_name ?? agent.business_name ?? "Agent")}
                </h3>
                <p className="text-sm text-muted">
                  {String(agent.contact_email ?? agent.phone_number ?? "")}
                </p>
              </div>
              <Status
                value={`${agent.verification_status} · ${agent.account_status}`}
              />
            </div>
            {canAssign && <AgentTeamAssignment agentId={String(agent.id)} supervisorId={agent.supervisor_id ? String(agent.supervisor_id) : ""} onSaved={onCreated} />}
            <div className="mt-4 flex gap-2">
              <button
                className="btn btn-success"
                disabled={busy}
                onClick={() => void update(agent.id as string, true)}
              ><UiText text={"Approve & activate"} /></button>
              <button
                className="btn btn-outline"
                disabled={busy}
                onClick={() => void update(agent.id as string, false)}
              ><UiText text={"Deactivate"} /></button>
            </div>
          </article>
        ))}
      </div>
    </Panel></SupervisorTeams>
  );
}

function Owners({
  rows,
  busy,
  review,
  reviewAsset,
}: {
  rows: Row[];
  busy: boolean;
  review: (id: string, approve: boolean) => void;
  reviewAsset: (id: string, approve: boolean) => void;
}) {
  return (
    <Panel
      title="Owner, manager and item verification"
      subtitle="Verify identity first, then verify authority over each physical item before enabling bookings."
    >
      <div className="grid gap-3">
        {rows.length === 0 ? (
          <Empty text="No verification requests." />
        ) : (
          rows.map((row) => {
            const claim = row.record_type === "asset_claim";
            const person = relation(row.owner_profiles);
            const asset = relation(row.rental_assets);
            return (
              <article
                className="soft-panel p-4"
                key={`${String(row.record_type)}-${String(row.id)}`}
              >
                <div className="flex flex-wrap justify-between gap-3">
                  <div>
                    <h3 className="font-semibold">
                      {claim
                        ? String(asset.display_name ?? "Asset claim")
                        : String(row.legal_name)}
                    </h3>
                    <p className="text-sm text-muted">
                      {claim
                        ? `${String(person.display_name ?? "Owner/manager")} · ${String(row.authority_type).replaceAll("_", " ")}`
                        : `${String(row.owner_type).replaceAll("_", " ")} · ${String(row.phone_number)}`}
                    </p>
                    <p className="mt-3 text-sm">
                      <UiText text={claim
                        ? `Identity: ${String(person.verification_status)} · Item: ${String(asset.verification_status)}`
                        : String(row.authorization_summary)} />
                    </p>
                  </div>
                  <Status value={String(row.status)} />
                </div>
                {claim &&
                ["pending", "rejected"].includes(String(row.status)) ? (
                  <div className="mt-4 flex gap-2">
                    <button
                      className="btn btn-success"
                      disabled={busy}
                      onClick={() => void reviewAsset(String(row.id), true)}
                    ><UiText text={"Verify authority and item"} /></button>
                    <button
                      className="btn btn-outline"
                      disabled={busy}
                      onClick={() => void reviewAsset(String(row.id), false)}
                    ><UiText text={"Reject"} /></button>
                  </div>
                ) : !claim &&
                  ["submitted", "under_review"].includes(String(row.status)) ? (
                  <div className="mt-4 flex gap-2">
                    <button
                      className="btn btn-success"
                      disabled={busy}
                      onClick={() => void review(String(row.id), true)}
                    ><UiText text={"Verify identity"} /></button>
                    <button
                      className="btn btn-outline"
                      disabled={busy}
                      onClick={() => void review(String(row.id), false)}
                    ><UiText text={"Reject"} /></button>
                  </div>
                ) : null}
              </article>
            );
          })
        )}
      </div>
    </Panel>
  );
}

function Reports({
  rows,
  busy,
  update,
}: {
  rows: Row[];
  busy: boolean;
  update: (id: string, status: string) => Promise<void>;
}) {
  return (
    <Panel
      title="Reports"
      subtitle="Review marketplace safety and listing reports."
    >
      <div className="grid gap-3">
        {rows.length === 0 ? (
          <Empty text="No reports have been submitted." />
        ) : (
          rows.map((row) => (
            <article
              className="rounded-2xl border border-brand-border bg-white p-4"
              key={String(row.id)}
            >
              <h3 className="font-semibold">{String(row.report_reason)}</h3>
              <p className="mt-1 text-sm text-muted">
                {String(row.details || "No additional details")}
              </p>
              <label className="mt-4 grid max-w-xs gap-2 text-sm font-semibold"><UiText text={"Status"} /><select
                  className="rounded-xl border border-brand-border bg-white p-3"
                  disabled={busy}
                  value={String(row.status)}
                  onChange={(event) =>
                    void update(String(row.id), event.target.value)
                  }
                >
                  {["open", "in_review", "resolved", "dismissed"].map(
                    (value) => (
                      <option key={value}>{value}</option>
                    ),
                  )}
                </select>
              </label>
            </article>
          ))
        )}
      </div>
    </Panel>
  );
}

function Promotions({
  rows,
  busy,
  toggle,
}: {
  rows: Row[];
  busy: boolean;
  toggle: (id: string, active: boolean) => Promise<void>;
}) {
  return (
    <Panel
      title="Promotions"
      subtitle="Control promotions shared by the mobile apps and website."
    >
      <div className="grid gap-3">
        {rows.length === 0 ? (
          <Empty text="No promotions available." />
        ) : (
          rows.map((row) => (
            <article
              className="rounded-2xl border border-brand-border bg-white p-4"
              key={String(row.id)}
            >
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <h3 className="font-semibold">{String(row.title)}</h3>
                  <p className="mt-1 text-sm text-muted">
                    {String(row.description || "")}
                  </p>
                  <p className="mt-2 text-xs font-semibold uppercase tracking-wide">
                    {String(row.placement)} · {String(row.visibility_scope)}
                  </p>
                </div>
                <Status value={row.is_active ? "active" : "paused"} />
              </div>
              <PromotionCategorySelect id={String(row.id)} initialIds={(row.target_category_ids ?? []) as string[]} />
              <button
                className="btn btn-outline mt-4"
                disabled={busy}
                onClick={() =>
                  void toggle(String(row.id), row.is_active !== true)
                }
              >
                <UiText text={row.is_active ? "Pause promotion" : "Activate promotion"} />
              </button>
            </article>
          ))
        )}
      </div>
    </Panel>
  );
}

function Notifications({
  rows,
  markRead,
}: {
  rows: Row[];
  markRead: (id: string) => Promise<void>;
}) {
  return (
    <Panel
      title="Notifications"
      subtitle="Account and marketplace activity from the shared Supabase notification stream."
    >
      <div className="grid gap-3">
        {rows.length === 0 ? (
          <Empty text="No notifications available." />
        ) : (
          rows.map((row) => (
            <article
              className={`rounded-2xl border p-4 ${row.read_at ? "border-brand-border bg-white" : "border-brand-green bg-brand-green-soft"}`}
              key={String(row.id)}
            >
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <h3 className="font-semibold">
                    {String(row.title || "Notification")}
                  </h3>
                  <p className="mt-1 text-sm">{String(row.body || "")}</p>
                  <p className="mt-2 text-xs text-muted">
                    {new Date(String(row.created_at)).toLocaleString()}
                  </p>
                </div>
                {!row.read_at ? (
                  <button
                    className="btn btn-outline"
                    onClick={() => void markRead(String(row.id))}
                  ><UiText text={"Mark read"} /></button>
                ) : (
                  <Status value="read" />
                )}
              </div>
            </article>
          ))
        )}
      </div>
    </Panel>
  );
}

function ProfilePanel({ rows, email }: { rows: Row[]; email: string }) {
  const profile = rows[0] ?? {};
  return (
    <Panel
      title="Profile"
      subtitle="The identity attached to this management account."
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Info
          label="Full name"
          value={String(profile.full_name || "Not provided")}
        />
        <Info label="Email" value={String(profile.account_email || email)} />
        <Info
          label="Username"
          value={String(profile.username || "Not provided")}
        />
        <Info
          label="Phone"
          value={String(profile.phone_number || "Not provided")}
        />
        <Info
          label="Language"
          value={String(profile.preferred_language || "sw")}
        />
      </div>
    </Panel>
  );
}

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div className="soft-panel p-4">
      <p className="text-xs font-bold uppercase tracking-[0.16em] text-muted">
        <UiText text={label} />
      </p>
      <p className="mt-2 font-semibold break-words">{value}</p>
    </div>
  );
}

function AddListingForm({ agentId }: { agentId: string }) {
  const supabase = useMemo(() => getBrowserSupabase(), []);
  const [categories, setCategories] = useState<Row[]>([]);
  const [areaDraft, setAreaDraft] = useState<{ wardId: string; name: string } | null>(null);
  const [photos, setPhotos] = useState<ListingPhoto[]>([]);
  const [preparing, setPreparing] = useState(false);
  const [extraDetails, setExtraDetails] = useState("");
  const [uploaded, setUploaded] = useState(false);
  const [draftId, setDraftId] = useState("");
  const mediaPaths = useRef(new Map<string, string>());
  const [progress, setProgress] = useState("");
  const [categoryId, setCategoryId] = useState("");
  const [locationId, setLocationId] = useState("");
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [price, setPrice] = useState("");
  const [ownerEnabled, setOwnerEnabled] = useState(false);
  const [ownerName, setOwnerName] = useState("");
  const [ownerPhone, setOwnerPhone] = useState("");
  const [ownerNotes, setOwnerNotes] = useState("");
  const [period, setPeriod] = useState("month");
  const [attributes, setAttributes] = useState<Row>({});
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  useEffect(() => {
    void supabase.from("agent_service_categories").select("asset_categories(id, name, slug, field_schema)").eq("agent_id", agentId).abortSignal(AbortSignal.timeout(10000)).then(({ data, error }) => {
      if (error) setMessage("Your categories could not be loaded. Please reload and try again.");
      else setCategories((data ?? []).map((row) => relation((row as Row).asset_categories)).filter(category=>category.slug!=="lodges-guesthouses"));
    });
  }, [agentId, supabase]);
  const selectedCategory = categories.find((item) => item.id === categoryId);
  const fields = schema(selectedCategory ?? {});
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy || preparing) return;
    if (!Number.isFinite(Number(price)) || Number(price) <= 0) { setMessage("Please enter a price greater than zero."); return; }
    if (!photos.length) { setMessage("Add at least one listing image before continuing."); return; }
    if (photos.length > (selectedCategory?.slug === "apartment" ? 15 : 8)) { setMessage("Too many images. Remove an image before adding more."); return; }
    setBusy(true); setMessage(null);
    try {
      let location = locationId;
      if (!location && areaDraft?.name.trim()) {
        const area = await supabase.rpc("ensure_ward_area", { p_ward_id: areaDraft.wardId, p_area_name: areaDraft.name.trim() } as never).abortSignal(AbortSignal.timeout(10000));
        if (area.error) throw area.error;
        const row = area.data?.[0] as Row | undefined;
        if (!row?.id || row.parent_id !== areaDraft.wardId || row.location_type !== "area") throw new Error("Invalid area");
        location = String(row.id); setLocationId(location);
      }
      if (!location) throw new Error("Choose area");
      let id = draftId;
      if (!id) {
        setProgress("Creating draft...");
        const values = { ...attributes };
        fields.filter((f) => f.active !== false && f.type === "boolean").forEach((f) => { values[String(f.key)] ??= false; });
        const result = await supabase.rpc("create_agent_listing_draft", {
          p_category_id: categoryId, p_location_id: location, p_title: title.trim(),
          p_description: [description.trim(), extraDetails.trim()].filter(Boolean).join("\n\n"),
          p_price_amount: Number(price), p_price_period: period, p_attributes: values,
          p_owner_name: ownerEnabled ? ownerName.trim() : null, p_owner_phone: ownerEnabled ? ownerPhone.trim() : null,
          p_owner_notes: ownerEnabled ? ownerNotes.trim() : null,
        } as never).abortSignal(AbortSignal.timeout(30000)) as unknown as { data: string | null; error: unknown };
        if (result.error || !result.data) throw result.error ?? new Error("No draft");
        id = String(result.data); setDraftId(id);
      }
      const session = (await supabase.auth.getSession()).data.session;
      const user = session?.user;
      if (!user || !session) throw new Error("Sign in required");
      for (const [index, photo] of photos.entries()) {
        setProgress("Uploading images...");
        let path = mediaPaths.current.get(photo.id);
        if (!path) {
          path = `${user.id}/${id}/image-${photo.id}.jpg`;
          await uploadListingPhoto(path, photo.blob, session.access_token);
          mediaPaths.current.set(photo.id, path);
        }
        const existing = await supabase.from("listing_media").select("id").eq("listing_id", id).eq("storage_path", path).abortSignal(AbortSignal.timeout(10000));
        if (existing.error) throw existing.error;
        if (!existing.data?.length) {
          const media = await supabase.from("listing_media").insert({ listing_id: id, media_type: "image", storage_path: path, display_order: index, is_cover: index === 0 } as never).abortSignal(AbortSignal.timeout(15000));
          if (media.error) throw media.error;
        }
      }
      setUploaded(true);
    } catch { setMessage("We could not finish saving. If a draft was created, retry here to finish its images. Check My listings before starting another draft."); }
    finally { setBusy(false); setProgress(""); }
  }

  if (uploaded) return <Panel title="Asset uploaded" subtitle="Your asset and images are saved. Complete submission below."><ListingPublication listingId={draftId} /></Panel>;
  return (
    <Panel
      title="Add asset"
      subtitle="Add details, choose an area and upload images. Then submit your asset for publication."
    >
      <form className="grid gap-4" onSubmit={submit}>
        <fieldset disabled={busy || !!draftId} className="grid min-w-0 gap-4">
        <Input label="Title" value={title} set={setTitle} required />
        <label className="grid gap-2 font-semibold"><UiText text={"Description"} /><textarea
            className="rounded-xl border border-brand-border bg-white p-3"
            minLength={10}
            rows={5}
            value={description}
            onChange={(event) => setDescription(event.target.value)}
            required
          />
        </label>
        <div className="grid gap-4 sm:grid-cols-2">
          <label className="grid gap-2 font-semibold"><UiText text={"Category"} /><select
              className="rounded-xl border border-brand-border bg-white p-3"
              value={categoryId}
              onChange={(event) => {
                setCategoryId(event.target.value);
                setAttributes({});
              }}
              required
            >
              <option value=""><UiText text={"Select category"} /></option>
              {categories.map((item) => (
                <option value={String(item.id)} key={String(item.id)}>
                  <UiText text={String(item.name)} />
                </option>
              ))}
            </select>
          </label>
          <SupervisorLocationChoice requireArea onChange={setLocationId} onAreaDraftChange={setAreaDraft} />
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <Input
            label="Price (TZS)"
            type="number"
            value={price}
            set={setPrice}
            required
          />
          <label className="grid gap-2 font-semibold"><UiText text={"Price period"} /><select
              className="rounded-xl border border-brand-border bg-white p-3"
              value={period}
              onChange={(event) => setPeriod(event.target.value)}
            >
              {["hour", "day", "week", "month", "year"].map((value) => (
                <option key={value}>{value}</option>
              ))}
            </select>
          </label>
        </div>
        <fieldset className="soft-panel grid gap-3 p-4"><legend className="font-semibold"><UiText text={"Owner details (optional and private)"} /></legend>
          <label className="flex gap-3"><input type="checkbox" checked={ownerEnabled} onChange={(event) => setOwnerEnabled(event.target.checked)} /><UiText text={"Add owner contact details"} /></label>
          <p className="text-sm text-muted"><UiText text={"Leave this off to create a listing without owner details. Entering a contact does not create or verify an owner account."} /></p>
          {ownerEnabled ? <><Input label="Owner name" value={ownerName} set={setOwnerName} required /><Input label="Owner phone" value={ownerPhone} set={setOwnerPhone} required /><Input label="Owner notes" value={ownerNotes} set={setOwnerNotes} /></> : null}
        </fieldset>
        {fields
          .filter((field) => field.active !== false)
          .map((field) => (
            <DynamicField
              key={String(field.key)}
              field={field}
              value={attributes[String(field.key)]}
              set={(value) =>
                setAttributes((current) => ({
                  ...current,
                  [String(field.key)]: value,
                }))
              }
            />
          ))}
        <label className="grid gap-2 font-semibold"><UiText text="Additional details" /><textarea className="field-input" rows={4} maxLength={5000} value={extraDetails} onChange={(e) => setExtraDetails(e.target.value)} /></label>
        <p className="text-sm"><UiText text="Add features, conditions or services not covered above. These details appear in the public description." /></p>
        </fieldset>
        <ListingImagePicker photos={photos} onChange={setPhotos} onBusy={setPreparing} disabled={busy || !!draftId} limit={selectedCategory?.slug === "apartment" ? 15 : 8} />
        {draftId && <p role="status"><UiText text="Draft saved. Retry to finish uploading its images." /></p>}
        {progress && <p role="status" aria-live="polite"><UiText text={progress} /></p>}
        {message ? (
          <p className="rounded-xl bg-brand-danger-soft p-3 text-sm text-brand-danger">
            <UiText text={message} />
          </p>
        ) : null}
        <button
          className="btn btn-success"
          disabled={busy || preparing || !categoryId || (!locationId && !areaDraft?.name.trim())}
        >
          <UiText text={busy ? "Uploading asset..." : "Upload asset"} />
        </button>
      </form>
    </Panel>
  );
}

function ListingEditor({
  listing,
  close,
  save,
}: {
  listing: Row;
  close: () => void;
  save: (values: Row) => void;
}) {
  const contact = relation(listing.owners);
  const [ownerName, setOwnerName] = useState(String(contact.full_name ?? ""));
  const [ownerPhone, setOwnerPhone] = useState(String(contact.phone_number ?? ""));
  const [ownerNotes, setOwnerNotes] = useState(String(contact.notes ?? ""));
  const [title, setTitle] = useState(String(listing.title ?? ""));
  const [description, setDescription] = useState(
    String(listing.description ?? ""),
  );
  const [price, setPrice] = useState(String(listing.price_amount ?? "0"));
  const [availability, setAvailability] = useState(
    String(listing.availability_status ?? "available"),
  );
  const fields = schema(listing.asset_categories as Row);
  const initial = (listing.listing_attributes as Row | null) ?? {};
  const [attributes, setAttributes] = useState<Row>(initial);
  return (
    <Modal title="Edit listing" close={close}>
      <form
        className="grid gap-4"
        onSubmit={(e) => {
          e.preventDefault();
          save({
            private_owner: { name: ownerName, phone: ownerPhone, notes: ownerNotes },
            title: title.trim(),
            description: description.trim(),
            price_amount: Number(price),
            availability_status: availability,
            listing_attributes: attributes,
          });
        }}
      >
        <Input label="Title" value={title} set={setTitle} required />
        <label className="grid gap-2 font-semibold"><UiText text={"Description"} /><textarea
            className="rounded-xl border border-brand-border p-3"
            rows={4}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            required
          />
        </label>
        <Input
          label="Price"
          value={price}
          set={setPrice}
          type="number"
          required
        />
        <label className="grid gap-2 font-semibold"><UiText text={"Availability"} /><select
            className="rounded-xl border border-brand-border bg-white p-3"
            value={availability}
            onChange={(e) => setAvailability(e.target.value)}
          >
            {["available", "reserved", "rented", "unavailable"].map((x) => (
              <option key={x}>{x}</option>
            ))}
          </select>
        </label>
        <fieldset className="soft-panel grid gap-3 p-4"><legend><UiText text={"Private owner contact (optional)"} /></legend><Input label="Owner name" value={ownerName} set={setOwnerName} required={Boolean(ownerPhone.trim() || ownerNotes.trim())} /><Input label="Owner phone" value={ownerPhone} set={setOwnerPhone} required={Boolean(ownerName.trim() || ownerNotes.trim())} /><Input label="Owner notes" value={ownerNotes} set={setOwnerNotes} /><p className="text-sm text-muted"><UiText text={"Clear all three fields to detach this private owner contact."} /></p></fieldset>
        {fields
          .filter((field) => field.active !== false)
          .map((field) => (
            <DynamicField
              key={field.key as string}
              field={field}
              value={attributes[field.key as string]}
              set={(value) =>
                setAttributes((current) => ({
                  ...current,
                  [field.key as string]: value,
                }))
              }
            />
          ))}
        <div className="flex gap-3">
          <button className="btn btn-success"><UiText text={"Save changes"} /></button>
          <button className="btn btn-outline" type="button" onClick={close}><UiText text={"Cancel"} /></button>
        </div>
      </form>
    </Modal>
  );
}

function CategoryEditor({
  category,
  close,
  save,
}: {
  category: Row;
  close: () => void;
  save: (values: Row) => void;
}) {
  const [fields, setFields] = useState<Row[]>(schema(category));
  const [label, setLabel] = useState("");
  const [type, setType] = useState("text");
  function addField() {
    const key = label
      .toLowerCase()
      .trim()
      .replace(/[^a-z0-9]+/g, "_")
      .replace(/^_+|_+$/g, "");
    if (!key || fields.some((field) => field.key === key)) return;
    setFields((current) => [
      ...current,
      {
        key,
        label: label.trim(),
        type,
        required: false,
        active: true,
        ...(type === "select" ? { options: ["Option 1"] } : {}),
      },
    ]);
    setLabel("");
  }
  return (
    <Modal title={`${String(category.name)} listing fields`} close={close}>
      <div className="grid gap-4">
        <div className="grid gap-3 rounded-2xl bg-brand-green-soft p-4 sm:grid-cols-[1fr_150px_auto]">
          <Input label="New field label" value={label} set={setLabel} />
          <label className="grid gap-2 font-semibold"><UiText text={"Type"} /><select
              className="rounded-xl border border-brand-border bg-white p-3"
              value={type}
              onChange={(e) => setType(e.target.value)}
            >
              {["text", "textarea", "number", "boolean", "select"].map((x) => (
                <option key={x}>{x}</option>
              ))}
            </select>
          </label>
          <button
            type="button"
            className="btn btn-success self-end"
            onClick={addField}
          ><UiText text={"Add field"} /></button>
        </div>
        {fields.map((field, index) => (
          <div
            className="rounded-2xl border border-brand-border p-4"
            key={field.key as string}
          >
            <div className="grid gap-3 sm:grid-cols-2">
              <Input
                label="Label"
                value={String(field.label)}
                set={(value) =>
                  setFields((current) =>
                    current.map((item, i) =>
                      i === index ? { ...item, label: value } : item,
                    ),
                  )
                }
              />
              <label className="flex items-center gap-2 pt-7 font-semibold">
                <input
                  type="checkbox"
                  checked={field.required === true}
                  onChange={(e) =>
                    setFields((current) =>
                      current.map((item, i) =>
                        i === index
                          ? { ...item, required: e.target.checked }
                          : item,
                      ),
                    )
                  }
                /><UiText text={"Required"} /></label>
            </div>
            <p className="mt-2 text-xs text-muted"><UiText text={"Stable key:"} />{String(field.key)} · {String(field.type)}
            </p>
            <button
              className="mt-3 text-sm font-semibold underline"
              onClick={() =>
                setFields((current) =>
                  current.map((item, i) =>
                    i === index
                      ? { ...item, active: item.active === false }
                      : item,
                  ),
                )
              }
            >
              <UiText text={field.active === false ? "Restore field" : "Retire field"} />
            </button>
          </div>
        ))}
        <div className="flex gap-3">
          <button
            className="btn btn-success"
            onClick={() => save({ field_schema: fields })}
          ><UiText text={"Save fields"} /></button>
          <button className="btn btn-outline" onClick={close}><UiText text={"Cancel"} /></button>
        </div>
      </div>
    </Modal>
  );
}

function DynamicField({
  field,
  value,
  set,
}: {
  field: Row;
  value: unknown;
  set: (value: unknown) => void;
}) {
  const label = `${String(field.label ?? field.key)}${field.required ? " *" : ""}`;
  if (field.type === "boolean")
    return (
      <label className="flex items-center gap-3 font-semibold">
        <input
          type="checkbox"
          checked={value === true}
          onChange={(e) => set(e.target.checked)}
        />
        <UiText text={label} />
      </label>
    );
  if (field.type === "select")
    return (
      <label className="grid gap-2 font-semibold">
        <UiText text={label} />
        <select
          className="rounded-xl border border-brand-border bg-white p-3"
          value={String(value ?? "")}
          onChange={(e) => set(e.target.value)}
          required={field.required === true}
        >
          <option value=""><UiText text={"Select"} /></option>
          {((field.options as unknown[]) ?? []).map((option) => (
            <option key={String(option)} value={String(option)}><UiText text={String(option)} /></option>
          ))}
        </select>
      </label>
    );
  if (field.type === "textarea") return <label className="grid gap-2 font-semibold"><UiText text={label} /><textarea className="field-input" rows={4} value={String(value ?? "")} required={field.required === true} onChange={(e) => set(e.target.value)} /></label>;
  return (
    <Input
      label={label}
      value={String(value ?? "")}
      set={(next) => set(field.type === "number" ? Number(next) : next)}
      type={field.type === "number" ? "number" : "text"}
      required={field.required === true}
    />
  );
}

function Modal({
  title,
  close,
  children,
}: {
  title: string;
  close: () => void;
  children: React.ReactNode;
}) {
  return (
    <div
      className="fixed inset-0 z-50 overflow-y-auto bg-brand-navy/60 p-4"
      role="dialog"
      aria-modal="true"
    >
      <div className="mx-auto my-8 max-w-2xl rounded-3xl bg-white p-6 shadow-2xl">
        <div className="mb-5 flex justify-between gap-4">
          <h2 className="font-heading text-2xl font-semibold"><UiText text={title} /></h2>
          <UiButton onClick={close} className="text-xl" aria-label="Close">
            ×
          </UiButton>
        </div>
        {children}
      </div>
    </div>
  );
}
function Panel({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle: string;
  children: React.ReactNode;
}) {
  return (
    <div className="surface-card p-5 sm:p-7">
      <h2 className="font-heading text-3xl font-semibold"><UiText text={title} /></h2>
      <p className="mt-2 mb-6 text-muted"><UiText text={subtitle} /></p>
      {children}
    </div>
  );
}
function Input({
  label,
  value,
  set,
  type = "text",
  required = false,
}: {
  label: string;
  value: string;
  set: (value: string) => void;
  type?: string;
  required?: boolean;
}) {
  return (
    <label className="grid gap-2 font-semibold">
      <UiText text={label} />
      <input
        className="rounded-xl border border-brand-border bg-white p-3"
        type={type}
        value={value}
        onChange={(e) => set(e.target.value)}
        required={required}
      />
    </label>
  );
}
function Status({ value }: { value: string }) {
  const normalized = value.toLowerCase().replaceAll(" ", "_");
  const palette = ["rejected", "suspended", "cancelled", "error"].includes(normalized) ? ["#fff1f2", "#9f1239"]
    : ["pending", "new", "confirmation_pending"].includes(normalized) ? ["#fff7df", "#78510b"]
    : ["active", "approved", "auto_approved", "admin_approved", "completed", "confirmed", "email_confirmed"].includes(normalized) ? ["#e1f2eb", "#145445"]
    : ["#edf1f5", "#40556a"];
  return <span className="h-fit rounded-full px-3 py-1 text-xs font-semibold" style={{ backgroundColor: palette[0], color: palette[1] }}><UiText text={value.replaceAll("_", " ")} /></span>;
}
function Empty({ text }: { text: string }) {
  return (
    <p className="rounded-2xl bg-brand-info-soft p-5 text-muted"><UiText text={text} /></p>
  );
}
function schema(row: Row | null | undefined): Row[] {
  return Array.isArray(row?.field_schema) ? (row.field_schema as Row[]) : [];
}
function relation(value: unknown): Row {
  if (Array.isArray(value)) return (value[0] as Row | undefined) ?? {};
  return value && typeof value === "object" ? (value as Row) : {};
}
function categoryName(listing: Row) {
  const value = listing.asset_categories as Row | Row[] | null;
  const category = Array.isArray(value) ? value[0] : value;
  return String(category?.name ?? "Listing");
}
function nestedTitle(value: unknown) {
  const row = Array.isArray(value) ? value[0] : value;
  return row && typeof row === "object"
    ? String((row as Row).title ?? "")
    : null;
}
function readError(error: unknown) {
  if (error && typeof error === "object" && "message" in error)
    return String(safeUserMessage(error));
  return "The request could not be completed.";
}
function isMissingFunction(error: unknown) {
  const text = readError(error).toLowerCase();
  return (
    text.includes("function") &&
    (text.includes("does not exist") || text.includes("schema cache"))
  );
}
async function withRetry<T>(
  operation: () => PromiseLike<T>,
  attempts = 2,
): Promise<T> {
  let lastError: unknown;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      const value = await operation();
      if (
        value &&
        typeof value === "object" &&
        "error" in value &&
        value.error
      ) {
        throw value.error;
      }
      return value;
    } catch (error) {
      lastError = error;
      if (attempt + 1 < attempts)
        await new Promise((resolve) => setTimeout(resolve, 350));
    }
  }
  throw lastError;
}
