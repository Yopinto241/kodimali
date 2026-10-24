"use client";

import Image from "next/image";
import Link from "next/link";
import { FormEvent, useEffect, useMemo, useState } from "react";
import { useLanguage } from "@/components/language-provider";
import { getBrowserSupabase } from "@/lib/supabase-browser";

type Row = Record<string, unknown>;

export function EventIndividualDetail({ kind, id }: { kind: "equipment" | "service"; id: string }) {
  const { language } = useLanguage();
  const sw = language === "sw";
  const supabase = getBrowserSupabase();
  const [row, setRow] = useState<Row | null>(null);
  const [images, setImages] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const nextPath = `/events/${kind}/${id}`;

  useEffect(() => {
    let active = true;
    const query = kind === "equipment"
      ? supabase.from("event_equipment_items").select("id,name,description,specifications,public_location_label,total_quantity,price_amount_tzs,price_unit,setup_minutes,return_buffer_minutes,transport_configuration,cleaning_configuration,return_procedure,security_deposit_tzs,damage_rules,cancellation_policy,media_paths,event_equipment_categories(name_sw,name_en)").eq("id", id).maybeSingle()
      : supabase.from("event_service_offerings").select("id,title,description,pricing_mode,price_amount_tzs,duration_minutes,requirements,travel_configuration,included_equipment,cancellation_policy,event_service_profiles(id,display_name,provider_kind,biography,experience_years,service_requirements,portfolio_media,event_service_areas(locations(name,location_type)))").eq("id", id).maybeSingle();
    void query.then(async ({ data, error }) => {
      if (!active) return;
      if (error || !data) { setLoading(false); return; }
      const value = data as unknown as Row;
      setRow(value);
      const profile = value.event_service_profiles as Row | null;
      const media = (kind === "equipment" ? value.media_paths : profile?.portfolio_media) as unknown;
      const paths = Array.isArray(media) ? media.filter((item): item is string => typeof item === "string") : [];
      const signed = await Promise.all(paths.slice(0, 8).map(async (path) => {
        if (path.startsWith("http://") || path.startsWith("https://")) return path;
        const { data: url } = await supabase.storage.from("listing-media").createSignedUrl(path, 3600);
        return url?.signedUrl ?? "";
      }));
      if (active) { setImages(signed.filter(Boolean)); setLoading(false); }
    });
    return () => { active = false; };
  }, [id, kind, supabase]);

  const title = String(row?.name ?? row?.title ?? "");
  const provider = (row?.event_service_profiles as Row | null) ?? null;
  const category = (row?.event_equipment_categories as Row | null) ?? null;
  const details = useMemo(() => kind === "equipment" ? [
    [sw ? "Kundi" : "Category", category ? String(sw ? category.name_sw : category.name_en) : "—"],
    [sw ? "Idadi iliyopo" : "Total stock", String(row?.total_quantity ?? "—")],
    [sw ? "Maandalizi" : "Setup", `${String(row?.setup_minutes ?? 0)} min`],
    [sw ? "Muda wa kurejesha" : "Return buffer", `${String(row?.return_buffer_minutes ?? 0)} min`],
  ] : [
    [sw ? "Mtoa huduma" : "Provider", String(provider?.display_name ?? "—")],
    [sw ? "Aina ya huduma" : "Service type", String(provider?.provider_kind ?? "").replaceAll("_", " ")],
    [sw ? "Uzoefu" : "Experience", `${String(provider?.experience_years ?? 0)} ${sw ? "miaka" : "years"}`],
    [sw ? "Muda" : "Duration", row?.duration_minutes ? `${String(row.duration_minutes)} min` : "—"],
  ], [category, kind, provider, row, sw]);

  async function requestBooking(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setNotice("");
    const { data: auth } = await supabase.auth.getUser();
    if (!auth.user) { window.location.assign(`/login?next=${encodeURIComponent(nextPath)}`); return; }
    const form = new FormData(event.currentTarget);
    const start = new Date(String(form.get("start")));
    const end = new Date(String(form.get("end")));
    const { data, error } = await supabase.rpc("create_individual_event_booking", {
      p_kind: kind, p_equipment_id: kind === "equipment" ? id : null,
      p_offering_id: kind === "service" ? id : null, p_start_at: start.toISOString(),
      p_end_at: end.toISOString(), p_quantity: kind === "equipment" ? Number(form.get("quantity")) : null,
      p_message: String(form.get("message") ?? "") || null,
    } as never);
    setBusy(false);
    if (error) { setNotice(error.message); return; }
    const booking = data as unknown as Row;
    setNotice(sw ? `Ombi limetumwa. Namba: ${String(booking.reference ?? "")}` : `Request sent. Reference: ${String(booking.reference ?? "")}`);
    event.currentTarget.reset();
  }

  if (loading) return <p className="py-16 text-center text-muted">{sw ? "Inapakia…" : "Loading…"}</p>;
  if (!row) return <div className="surface-card p-8"><h1 className="font-heading text-3xl font-semibold">{sw ? "Haijapatikana" : "Not found"}</h1><Link className="btn btn-outline mt-5" href="/events">{sw ? "Rudi kwenye Events" : "Back to Events"}</Link></div>;

  return <div className="space-y-8 pb-16">
    <Link href="/events#individual-marketplace" className="inline-flex font-semibold text-brand-teal">← {sw ? "Vifaa na huduma" : "Equipment and services"}</Link>
    <section className="grid gap-8 lg:grid-cols-[1.15fr_.85fr]">
      <div>
        {images.length ? <div className="grid gap-3 sm:grid-cols-2">{images.map((src, index) => <div className={`relative overflow-hidden rounded-3xl bg-brand-card-soft ${index === 0 ? "aspect-[4/3] sm:col-span-2" : "aspect-square"}`} key={src}><Image src={src} alt={`${title} ${index + 1}`} fill priority={index === 0} sizes="(max-width: 1024px) 100vw, 60vw" className="object-cover transition duration-700 hover:scale-[1.03]" /></div>)}</div> : <div className="aspect-[4/3] rounded-3xl bg-[linear-gradient(145deg,#dfece5,#b9d8d0)]" />}
      </div>
      <div>
        <p className="eyebrow">{kind === "equipment" ? (sw ? "Kifaa kilichothibitishwa" : "Verified equipment") : (sw ? "Mtoa huduma aliyethibitishwa" : "Verified professional")}</p>
        <h1 className="mt-3 font-heading text-4xl font-semibold">{title}</h1>
        <p className="mt-4 text-muted">{String(row.description ?? provider?.biography ?? "")}</p>
        <p className="mt-5 text-2xl font-bold">{row.price_amount_tzs == null ? (sw ? "Omba quotation" : "Request a quote") : `TZS ${Number(row.price_amount_tzs).toLocaleString()}${kind === "equipment" ? ` · ${String(row.price_unit).replaceAll("_", " ")}` : ""}`}</p>
        <div className="mt-6 grid grid-cols-2 gap-3">{details.map(([label, value]) => <div className="soft-panel p-4" key={label}><p className="text-xs font-bold uppercase text-muted">{label}</p><p className="mt-1 font-semibold">{value}</p></div>)}</div>
      </div>
    </section>
    <section className="grid gap-6 lg:grid-cols-[1fr_.8fr]">
      <div className="surface-card p-6"><h2 className="font-heading text-2xl font-semibold">{sw ? "Masharti muhimu" : "Important details"}</h2><Info label={sw ? "Eneo" : "Location"} value={String(row.public_location_label ?? (sw ? "Eneo kamili hutolewa baada ya uthibitisho" : "Exact location is shared after approval"))} /><Info label={sw ? "Usafiri na maandalizi" : "Travel and setup"} value={formatValue(kind === "equipment" ? row.transport_configuration : row.travel_configuration)} /><Info label={sw ? "Vifaa vinavyojumuishwa" : "Included equipment"} value={String(row.included_equipment ?? "—")} /><Info label={sw ? "Dhamana" : "Security deposit"} value={row.security_deposit_tzs ? `TZS ${Number(row.security_deposit_tzs).toLocaleString()}` : "—"} /><Info label={sw ? "Uharibifu na urejeshaji" : "Damage and return"} value={String(row.damage_rules ?? row.return_procedure ?? "—")} /><Info label={sw ? "Kughairi" : "Cancellation"} value={String(row.cancellation_policy ?? "—")} /></div>
      <form className="surface-card p-6" onSubmit={requestBooking}><h2 className="font-heading text-2xl font-semibold">{sw ? "Tuma ombi la booking" : "Request this booking"}</h2><p className="mt-2 text-sm text-muted">{sw ? "Mtoa huduma atakagua muda na kukutumia quotation. Malipo ya mtandaoni hayajawashwa." : "The provider will confirm availability and send a quote. Online collection is not enabled."}</p><label className="field-label mt-5 block">{sw ? "Mwanzo" : "Starts"}<input className="field-input mt-2" type="datetime-local" name="start" required /></label><label className="field-label mt-4 block">{sw ? "Mwisho" : "Ends"}<input className="field-input mt-2" type="datetime-local" name="end" required /></label>{kind === "equipment" ? <label className="field-label mt-4 block">{sw ? "Idadi" : "Quantity"}<input className="field-input mt-2" type="number" name="quantity" min="1" max={Number(row.total_quantity)} defaultValue="1" required /></label> : null}<label className="field-label mt-4 block">{sw ? "Maelezo ya ombi" : "Request notes"}<textarea className="field-input mt-2 min-h-28" name="message" /></label><button className="btn btn-success mt-5 w-full" disabled={busy}>{busy ? (sw ? "Inatuma…" : "Sending…") : (sw ? "Tuma ombi" : "Send request")}</button>{notice ? <p className="mt-4 rounded-2xl bg-brand-info-soft p-4 text-sm font-semibold" role="status">{notice}</p> : null}</form>
    </section>
  </div>;
}

function Info({ label, value }: { label: string; value: string }) { return <div className="mt-5 border-t border-brand-border pt-4"><h3 className="font-semibold">{label}</h3><p className="mt-1 whitespace-pre-wrap text-sm text-muted">{value}</p></div>; }
function formatValue(value: unknown) { if (!value) return "—"; if (typeof value === "string") return value; try { return JSON.stringify(value, null, 2); } catch { return "—"; } }
