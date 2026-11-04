"use client";
import { safeUserMessage } from "@/lib/user-message";
import { translateUiPrompt } from "@/lib/ui-translation";
import { UiInput, UiText } from "@/components/ui-text";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { getBrowserSupabase } from "@/lib/supabase-browser";

import { ReferralFinancePanel } from "@/components/information-admin-workspace";
import { hasPermission } from "@/lib/manage-access";

type Row = Record<string, unknown>;
const switches = [
  {
    key: "contact_payments_enabled",
    label: "Contact number",
    on: "Payment required",
    off: "Free access",
  },
  {
    key: "chat_payments_enabled",
    label: "Private chat",
    on: "Payment required",
    off: "Free access",
  },
  {
    key: "agent_listing_payments_enabled",
    label: "Listing publication",
    on: "Payment required",
    off: "Free publication",
  },
  {
    key: "subscription_payments_enabled",
    label: "Agent subscriptions",
    on: "SonicPesa payments enabled",
    off: "Purchasing paused",
  },
  {
    key: "listing_boost_payments_enabled",
    label: "Featured campaigns",
    on: "Payment required",
    off: "Free activation",
  },
  {
    key: "booking_payments_enabled",
    label: "Customer pay and book",
    on: "SonicPesa payments enabled",
    off: "Checkout paused",
  },
  {
    key: "event_payments_enabled",
    label: "Events deposits and balances",
    on: "SonicPesa payments enabled",
    off: "Checkout paused",
  },
] as const;

export function BusinessOperations({
  role,
  agentId,
  permissions = [],
}: {
  role: "admin" | "agent";
  agentId: string | null;
  permissions?: readonly string[];
}) {
  const supabase = useMemo(() => getBrowserSupabase(), []);
  const [dashboard, setDashboard] = useState<Row>({});
  const [settings, setSettings] = useState<Row>({});
  const [plans, setPlans] = useState<Row[]>([]);
  const [payments, setPayments] = useState<Row[]>([]);
  const [boosts, setBoosts] = useState<Row[]>([]);
  const [risks, setRisks] = useState<Row[]>([]);
  const [refunds, setRefunds] = useState<Row[]>([]);
  const [receipts, setReceipts] = useState<Row[]>([]);
  const [campaignPerformance, setCampaignPerformance] = useState<Row[]>([]);
  const [listings, setListings] = useState<Row[]>([]);
  const [phone, setPhone] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");

  const load = useCallback(async () => {
    setMessage("");
    if (role === "admin") {
      const allowed = (permission: string) => hasPermission(permissions, permission);
      const empty = { data: null, error: null };
      const [
        analytics,
        config,
        paymentRows,
        boostRows,
        riskRows,
        refundRows,
        performanceRows,
      ] = await Promise.all([
        allowed("analytics.view") ? supabase.rpc("get_admin_business_analytics", { p_days: 30 } as never) : Promise.resolve(empty),
        allowed("*") ? supabase
          .from("marketplace_settings")
          .select("*")
          .eq("id", true)
          .maybeSingle() : Promise.resolve(empty),
        allowed("payments.manage") ? supabase
          .from("agent_commercial_payments")
          .select(
            "id, product_type, requested_amount, payment_status, created_at, agents(business_name)",
          )
          .order("created_at", { ascending: false })
          .limit(50) : Promise.resolve(empty),
        allowed("boosts.manage") ? supabase
          .from("listing_boosts")
          .select(
            "id, listing_id, placement, duration_days, amount_tzs, status, starts_at, ends_at, listings(title), agents(business_name)",
          )
          .order("created_at", { ascending: false })
          .limit(50) : Promise.resolve(empty),
        allowed("risk.manage") ? supabase
          .from("platform_risk_flags")
          .select("*")
          .order("created_at", { ascending: false })
          .limit(50) : Promise.resolve(empty),
        allowed("refunds.manage") ? supabase
          .from("payment_refunds")
          .select("*")
          .order("created_at", { ascending: false })
          .limit(50) : Promise.resolve(empty),
        allowed("analytics.view") ? supabase.rpc("get_platform_promotion_performance", {
          p_days: 30,
        } as never) : Promise.resolve(empty),
      ]);
      const failed = [analytics, config, paymentRows, boostRows, riskRows, refundRows, performanceRows].find((result) => result.error);
      if (failed?.error) setMessage(safeUserMessage(failed.error));
      setDashboard((analytics.data as Row | null) ?? {});
      setSettings((config.data as Row | null) ?? {});
      setPayments((paymentRows.data as Row[] | null) ?? []);
      setBoosts((boostRows.data as Row[] | null) ?? []);
      setRisks((riskRows.data as Row[] | null) ?? []);
      setRefunds((refundRows.data as Row[] | null) ?? []);
      setCampaignPerformance((performanceRows.data as Row[] | null) ?? []);
    } else {
      const [summary, planRows, boostRows, receiptRows, listingRows] =
        await Promise.all([
          supabase.rpc("get_my_agent_business_dashboard"),
          supabase
            .from("agent_subscription_plans")
            .select("*")
            .eq("is_active", true)
            .order("monthly_price_tzs"),
          supabase
            .from("listing_boosts")
            .select("*, listings(title)")
            .order("created_at", { ascending: false }),
          supabase
            .from("payment_receipts")
            .select("*")
            .order("issued_at", { ascending: false })
            .limit(50),
          supabase
            .from("listings")
            .select("id,title,status")
            .eq("agent_id", agentId ?? "")
            .order("created_at", { ascending: false }),
        ]);
      setDashboard((summary.data as Row | null) ?? {});
      setPlans((planRows.data as Row[] | null) ?? []);
      setBoosts((boostRows.data as Row[] | null) ?? []);
      setReceipts((receiptRows.data as Row[] | null) ?? []);
      setListings((listingRows.data as Row[] | null) ?? []);
    }
  }, [agentId, role, supabase, permissions]);

  useEffect(() => {
    queueMicrotask(() => void load());
  }, [load]);

  async function toggle(key: string, next: boolean, offLabel: string) {
    const action = next
      ? "Enable payments"
      : offLabel.toLowerCase().includes("paused")
        ? "Pause payments"
        : "Make free";
    if (
      !window.confirm(translateUiPrompt(`${action} for this service? This affects every app and remains active after logout.`),
      )
    )
      return;
    setBusy(true);
    const result = await supabase
      .from("marketplace_settings")
      .upsert({ id: true, [key]: next } as never);
    setMessage((result.error?.message ? safeUserMessage(result.error?.message) : null) ?? "Payment setting saved globally.");
    setBusy(false);
    await load();
  }

  async function commercialPayment(
    productType: "subscription" | "listing_boost",
    id: string,
  ) {
    if (phone.trim().length < 8) {
      setMessage("Enter the agent payment phone number first.");
      return;
    }
    setBusy(true);
    const result = await supabase.functions.invoke(
      "create-agent-commercial-payment",
      {
        body: {
          product_type: productType,
          phone_number: phone.trim(),
          ...(productType === "subscription"
            ? { plan_id: id }
            : { listing_boost_id: id }),
        },
      },
    );
    setMessage(
      (result.error?.message ? safeUserMessage(result.error?.message) : null) ??
        String(
          (result.data as Row | null)?.message ??
            "Payment request sent. Confirm it on the phone.",
        ),
    );
    setBusy(false);
    await load();
  }

  async function createBoost(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    const listingId = String(data.get("listing"));
    const placement = String(data.get("placement"));
    const duration = Number(data.get("duration"));
    const amount = duration === 3 ? 5000 : duration === 7 ? 10000 : 30000;
    setBusy(true);
    const result = await supabase
      .from("listing_boosts")
      .insert({
        listing_id: listingId,
        agent_id: agentId,
        placement,
        duration_days: duration,
        amount_tzs: amount,
      } as never)
      .select("id")
      .single();
    if (result.error) setMessage(safeUserMessage(result.error));
    else {
      setMessage("Campaign created. Complete payment to activate it.");
      await commercialPayment("listing_boost", String((result.data as Row).id));
    }
    setBusy(false);
    await load();
  }

  async function update(table: string, id: string, status: string) {
    if (!window.confirm(translateUiPrompt(`Change this record to ${status}?`))) return;
    setBusy(true);
    const result = await supabase
      .from(table)
      .update({
        status,
        ...(status === "resolved"
          ? { resolved_at: new Date().toISOString() }
          : {}),
      } as never)
      .eq("id", id);
    setMessage((result.error?.message ? safeUserMessage(result.error?.message) : null) ?? "Operation completed.");
    setBusy(false);
    await load();
  }

  return (
    <div className="grid gap-6">
      <section className="surface-card p-6">
        <h2 className="font-heading text-3xl font-semibold">
          <UiText text={role === "admin" ? "Business operations" : "Agent business centre"} />
        </h2>
        <p className="mt-2 text-muted"><UiText text={"Live Supabase analytics and commercial workflows."} /></p>
        <div className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {Object.entries(dashboard)
            .filter(([, value]) => typeof value !== "object")
            .slice(0, 12)
            .map(([key, value]) => (
              <div className="soft-panel p-4" key={key}>
                <p className="text-xs font-bold uppercase text-muted">
                  <UiText text={key.replaceAll("_", " ")} />
                </p>
                <p className="mt-2 text-xl font-bold">{String(value ?? 0)}</p>
              </div>
            ))}
        </div>
      </section>
      {role === "admin" && hasPermission(permissions, "payments.manage") ? <ReferralFinancePanel /> : null}
      {message ? (
        <p className="rounded-xl bg-brand-info-soft p-4" role="status">
          <UiText text={message} />
        </p>
      ) : null}
      {role === "admin" ? (
        <>
          {hasPermission(permissions, "*") ? <section className="surface-card p-6">
            <h2 className="font-heading text-2xl font-semibold"><UiText text={"Global payment switches"} /></h2>
            <p className="mt-2 text-sm text-muted"><UiText text={"Admin-only settings shared by the website and mobile apps. Paused checkout does not grant paid products for free."} /></p>
            <div className="mt-5 grid gap-3">
              {switches.map(({ key, label, on, off }) => (
                <label
                  className="flex items-center justify-between gap-4 rounded-xl border border-brand-border p-4"
                  key={key}
                >
                  <span>
                    <strong><UiText text={label} /></strong>
                    <span className="block text-xs text-muted">
                      <UiText text={settings[key] === true ? on : off} />
                    </span>
                  </span>
                  <input
                    type="checkbox"
                    checked={settings[key] === true}
                    disabled={busy}
                    onChange={(e) => void toggle(key, e.target.checked, off)}
                  />
                </label>
              ))}
            </div>
          </section> : null}
          {hasPermission(permissions, "payments.manage") ? <OperationList title="Commercial payments" rows={payments} /> : null}
          {hasPermission(permissions, "analytics.view") ? <OperationList
            title="Sponsored campaign performance (30 days)"
            rows={campaignPerformance.map((row) => ({
              ...row,
              id: row.promotion_id,
              status: `${row.impressions} impressions · ${row.clicks} clicks · ${row.click_through_rate}% CTR`,
            }))}
          /> : null}
          {hasPermission(permissions, "boosts.manage") ? <OperationList
            title="Featured campaigns"
            rows={boosts}
            actions={(row) =>
              row.status === "pending" ? (
                <button
                  className="btn btn-success"
                  onClick={() =>
                    void update("listing_boosts", String(row.id), "active")
                  }
                ><UiText text={"Approve"} /></button>
              ) : null
            }
          /> : null}
          {hasPermission(permissions, "risk.manage") ? <OperationList
            title="Risk and fraud flags"
            rows={risks}
            actions={(row) => (
              <button
                className="btn btn-outline"
                onClick={() =>
                  void update("platform_risk_flags", String(row.id), "resolved")
                }
              ><UiText text={"Resolve"} /></button>
            )}
          /> : null}
          {hasPermission(permissions, "refunds.manage") ? <OperationList
            title="Refund requests"
            rows={refunds}
            actions={(row) => (
              <>
                <button
                  className="btn btn-success"
                  onClick={() =>
                    void update("payment_refunds", String(row.id), "approved")
                  }
                ><UiText text={"Approve"} /></button>
                <button
                  className="btn btn-outline"
                  onClick={() =>
                    void update("payment_refunds", String(row.id), "rejected")
                  }
                ><UiText text={"Reject"} /></button>
              </>
            )}
          /> : null}
        </>
      ) : (
        <>
          <section className="surface-card p-6">
            <h2 className="font-heading text-2xl font-semibold"><UiText text={"Choose a subscription"} /></h2>
            <label className="field-label mt-4"><UiText text={"Payment phone"} /><UiInput
                className="field-input mt-2"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="255..."
              />
            </label>
            <div className="mt-5 grid gap-4 md:grid-cols-2">
              {plans.map((plan) => (
                <article className="soft-panel p-5" key={String(plan.id)}>
                  <h3 className="font-heading text-2xl font-semibold">
                    {String(plan.name)}
                  </h3>
                  <p className="mt-2 text-xl font-bold">
                    TZS {String(plan.monthly_price_tzs)}<UiText text={" / month"} /></p>
                  <p className="mt-2 text-sm text-muted">
                    <UiText text={plan.listing_limit == null
                      ? "Unlimited listings"
                      : `${String(plan.listing_limit)} listings`} />{" "}<UiText text={"· Publication fee TZS"} />{String(plan.publication_fee_tzs)}
                  </p>
                  <button
                    disabled={busy}
                    className="btn btn-success mt-4"
                    onClick={() =>
                      void commercialPayment("subscription", String(plan.id))
                    }
                  ><UiText text={"Select"} />{String(plan.name)}
                  </button>
                </article>
              ))}
            </div>
          </section>
          <section className="surface-card p-6">
            <h2 className="font-heading text-2xl font-semibold"><UiText text={"Promote a listing"} /></h2>
            <form
              className="mt-5 grid gap-4 sm:grid-cols-3"
              onSubmit={(e) => void createBoost(e)}
            >
              <select className="field-input" name="listing" required>
                <option value=""><UiText text={"Select listing"} /></option>
                {listings.map((row) => (
                  <option key={String(row.id)} value={String(row.id)}>
                    {String(row.title)}
                  </option>
                ))}
              </select>
              <select className="field-input" name="placement">
                <option value="featured"><UiText text={"Featured"} /></option>
                <option value="homepage"><UiText text={"Homepage"} /></option>
                <option value="search_top"><UiText text={"Top of search"} /></option>
                <option value="regional"><UiText text={"Regional"} /></option>
                <option value="category"><UiText text={"Category"} /></option>
              </select>
              <select className="field-input" name="duration">
                <option value="3"><UiText text={"3 days · TZS 5,000"} /></option>
                <option value="7"><UiText text={"7 days · TZS 10,000"} /></option>
                <option value="30"><UiText text={"30 days · TZS 30,000"} /></option>
              </select>
              <button className="btn btn-success" disabled={busy}><UiText text={"Create and pay"} /></button>
            </form>
          </section>
          <OperationList title="My featured campaigns" rows={boosts} />
          <OperationList title="Receipts" rows={receipts} />
        </>
      )}
    </div>
  );
}

function OperationList({
  title,
  rows,
  actions,
}: {
  title: string;
  rows: Row[];
  actions?: (row: Row) => React.ReactNode;
}) {
  return (
    <section className="surface-card p-6">
      <h2 className="font-heading text-2xl font-semibold"><UiText text={title} /></h2>
      <div className="mt-4 grid gap-3">
        {rows.length === 0 ? (
          <p className="text-muted"><UiText text={"No records."} /></p>
        ) : (
          rows.map((row) => (
            <article
              className="rounded-xl border border-brand-border p-4"
              key={String(row.id)}
            >
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="font-semibold">
                    {String(
                      row.title ??
                        row.product_type ??
                        row.risk_type ??
                        row.payment_kind ??
                        row.id,
                    )}
                  </p>
                  <p className="mt-1 text-xs text-muted">
                    {String(row.status ?? row.payment_status ?? "recorded")} ·{" "}
                    {String(row.amount_tzs ?? row.requested_amount ?? "")}{" "}
                    {row.created_at
                      ? new Date(String(row.created_at)).toLocaleString()
                      : ""}
                  </p>
                </div>
                <div className="flex gap-2">{actions?.(row)}</div>
              </div>
            </article>
          ))
        )}
      </div>
    </section>
  );
}
