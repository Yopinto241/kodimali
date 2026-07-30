"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";
import { getBrowserSupabase } from "@/lib/supabase-browser";

type Row = Record<string, unknown>;

export function ComparisonWorkspace() {
  const supabase = useMemo(() => getBrowserSupabase(), []);
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const ids = JSON.parse(localStorage.getItem("kodimali-comparison-listings") || "[]") as string[];
    void Promise.all(ids.map(async (id) => {
      const result = await supabase.rpc("get_public_listing_detail", { p_listing_id: id } as never);
      const value = Array.isArray(result.data) ? result.data[0] : result.data;
      return value ? { ...(value as Row), listing_id: id } : null;
    })).then((items) => { setRows(items.filter(Boolean) as Row[]); setLoading(false); });
  }, [supabase]);

  function clear() {
    localStorage.removeItem("kodimali-comparison-listings");
    setRows([]);
  }

  if (loading) return <p className="surface-card p-6">Loading comparison...</p>;
  if (rows.length === 0) return <div className="surface-card p-8"><h2 className="font-heading text-2xl font-semibold">No listings selected</h2><p className="mt-2 text-muted">Use Compare on any listing card. You can compare up to four listings.</p><Link href="/listings" className="btn btn-primary mt-5">Browse listings</Link></div>;

  const attributes = Array.from(new Set(rows.flatMap((row) => Object.keys((row.listing_attributes as Row | null) ?? {}))));
  const periods = new Set(rows.map((row) => String(row.price_period ?? "")));
  const pricesComparable = periods.size === 1 && rows.every((row) => Number.isFinite(Number(row.price_amount)));
  const lowestPrice = pricesComparable ? Math.min(...rows.map((row) => Number(row.price_amount))) : null;
  const completeness = rows.map((row) => Object.values((row.listing_attributes as Row | null) ?? {}).filter((value) => value !== null && value !== "" && value !== false).length);
  const mostComplete = Math.max(...completeness);
  const differentAttributes = attributes.filter((key) => new Set(rows.map((row) => JSON.stringify(((row.listing_attributes as Row | null) ?? {})[key] ?? null))).size > 1);

  return <div className="surface-card p-4 sm:p-6">
    <div className="mb-5 flex flex-wrap items-center justify-between gap-3"><p className="text-sm text-muted">Comparing {rows.length} listings</p><button className="btn btn-outline" onClick={clear}>Clear comparison</button></div>
    <section className="mb-6 grid gap-3 md:grid-cols-3" aria-label="Comparison strategy">
      <ComparisonInsight title="Price decision" value={pricesComparable ? `Lowest: TZS ${formatNumber(lowestPrice!)}` : "Compare periods first"} detail={pricesComparable ? "Prices use the same period, so the lowest-price marker is reliable." : "These listings use different price periods. Change your shortlist or calculate total cost for your intended duration."} />
      <ComparisonInsight title="Information quality" value={`${mostComplete} details supplied`} detail="The Most detailed marker identifies the listing with the most completed category fields; verify important facts with the agent." />
      <ComparisonInsight title="Key differences" value={`${differentAttributes.length} found`} detail={differentAttributes.length ? `Focus first on: ${differentAttributes.slice(0, 3).map((key) => key.replaceAll("_", " ")).join(", ")}.` : "The supplied category details are the same; decide using location, price and agent trust."} />
    </section>
    <div className="mb-6 rounded-2xl bg-brand-mist p-4 text-sm text-brand-ink"><strong>Recommended strategy:</strong> confirm the price period, remove listings outside your budget, compare the highlighted differences, then open each listing to check agent trust and exact location before paying to contact.</div>
    <div className="overflow-x-auto">
    <table className="w-full min-w-[720px] border-collapse text-left">
      <thead><tr><th className="border-b border-brand-border p-3">Detail</th>{rows.map((row, index) => <th className="border-b border-brand-border p-3" key={String(row.listing_id)}><Link className="text-brand-navy underline" href={`/listing/${row.listing_id}`}>{String(row.title)}</Link><div className="mt-2 flex flex-wrap gap-1">{lowestPrice !== null && Number(row.price_amount) === lowestPrice ? <Marker>Lowest price</Marker> : null}{completeness[index] === mostComplete ? <Marker>Most detailed</Marker> : null}</div></th>)}</tr></thead>
      <tbody>
        <CompareRow label="Price" rows={rows} value={(row) => `TZS ${formatNumber(row.price_amount)} / ${row.price_period ?? ""}`} />
        <CompareRow label="Location" rows={rows} value={(row) => String(row.public_location_label ?? "-")} />
        <CompareRow label="Availability" rows={rows} value={(row) => String(row.availability_status ?? "available")} />
        {differentAttributes.map((key) => <CompareRow key={key} label={key.replaceAll("_", " ")} rows={rows} emphasized value={(row) => displayValue(((row.listing_attributes as Row | null) ?? {})[key])} />)}
        {attributes.filter((key) => !differentAttributes.includes(key)).map((key) => <CompareRow key={key} label={key.replaceAll("_", " ")} rows={rows} value={(row) => displayValue(((row.listing_attributes as Row | null) ?? {})[key])} />)}
      </tbody>
    </table>
    </div>
  </div>;
}

function CompareRow({ label, rows, value, emphasized = false }: { label: string; rows: Row[]; value: (row: Row) => string; emphasized?: boolean }) {
  return <tr className={emphasized ? "bg-amber-50" : undefined}><th className="border-b border-brand-border p-3 capitalize">{label}{emphasized ? <span className="ml-2 text-xs text-amber-700">Differs</span> : null}</th>{rows.map((row) => <td className="border-b border-brand-border p-3 text-muted" key={String(row.listing_id)}>{value(row)}</td>)}</tr>;
}

function ComparisonInsight({ title, value, detail }: { title: string; value: string; detail: string }) {
  return <div className="rounded-2xl border border-brand-border bg-white p-4"><p className="text-xs font-semibold uppercase tracking-wide text-muted">{title}</p><p className="mt-2 font-heading text-lg font-semibold text-brand-ink">{value}</p><p className="mt-2 text-sm text-muted">{detail}</p></div>;
}

function Marker({ children }: { children: ReactNode }) {
  return <span className="rounded-full bg-brand-navy px-2 py-1 text-[11px] font-semibold text-white">{children}</span>;
}

function formatNumber(value: unknown) {
  const number = Number(value);
  return Number.isFinite(number) ? new Intl.NumberFormat("en-TZ", { maximumFractionDigits: 0 }).format(number) : "-";
}

function displayValue(value: unknown) {
  if (value === null || value === undefined || value === "") return "-";
  if (typeof value === "boolean") return value ? "Yes" : "No";
  if (Array.isArray(value)) return value.join(", ");
  return String(value);
}
