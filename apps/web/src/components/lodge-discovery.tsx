"use client";
import Link from "next/link";
import {
  useCallback,
  useEffect,
  useState,
  useRef,
  type FormEvent,
} from "react";
import { getLodgeClient } from "@/lib/lodge-client";
import { useLanguage } from "@/components/language-provider";
import { UiText } from "@/components/ui-text";
import { NavigationIndicator } from "@/components/navigation-progress";
import { EventLocationFields } from "@/components/event-location-fields";
import { DirectMediaImage } from "@/components/direct-media-image";
import { lodgeUserMessage } from "@/lib/lodge-errors";
import type { LodgeRow } from "@/lib/lodge-forms";
export function LodgeDiscovery({ id }: { id?: string }) {
  const db = getLodgeClient(),
    { language } = useLanguage();
  const generation = useRef(0);
  const [requests, setRequests] = useState<LodgeRow[]>([]);
  const [signedIn, setSignedIn] = useState(false);
  const [requestedType, setRequestedType] = useState("");
  const [data, setData] = useState<LodgeRow>({}),
    [search, setSearch] = useState(""),
    [location, setLocation] = useState(""),
    [arrival, setArrival] = useState(""),
    [departure, setDeparture] = useState(""),
    [offset, setOffset] = useState(0);
  const [images, setImages] = useState<Record<string, string>>({}),
    [loading, setLoading] = useState(true),
    [busy, setBusy] = useState(false),
    [message, setMessage] = useState("");
  const load = useCallback(async () => {
    const request = ++generation.current;
    setLoading(true);
    setMessage("");
    setData({});
    setImages({});
    setRequests([]);
    try {
      const r = await db.rpc("public_lodges", {
        p_id: id ?? null,
        p_search: search,
        p_location: location || null,
        p_offset: offset,
        p_limit: 20,
        p_arrival: arrival || null,
        p_departure: departure || null,
      });
      if (r.error) throw r.error;
      const result = r.data as LodgeRow;
      if (request !== generation.current) return;
      setData(result);
      if (id) {
        const session = await db.auth.getSession();
        if (session.data.session) {
          const status = await db.rpc("lodge_my_requests", { p_lodge: id });
          if (status.error) throw status.error;
          if (request === generation.current)
            setRequests(
              Array.isArray(status.data) ? (status.data as LodgeRow[]) : [],
            );
        }
      }
      const paths = ((result.rows as LodgeRow[]) ?? []).flatMap((r) => [
        ...(Array.isArray(r.photos) ? (r.photos as string[]) : []),
        ...(Array.isArray(r.room_types)
          ? (r.room_types as LodgeRow[])
          : []
        ).flatMap((t) => (t.main_image ? [String(t.main_image)] : [])),
      ]);
      if (paths.length) {
        const signed = await db.storage
          .from("lodge-media")
          .createSignedUrls([...new Set(paths)], 3600);
        if (signed.error) throw signed.error;
        if (request === generation.current)
          setImages(
            Object.fromEntries(
              (signed.data ?? [])
                .filter((s) => s.signedUrl && s.path)
                .map((s) => [s.path!, s.signedUrl!]),
            ),
          );
      }
    } catch (e) {
      if (request === generation.current)
        setMessage(lodgeUserMessage(e, language));
    } finally {
      if (request === generation.current) setLoading(false);
    }
  }, [db, id, search, location, offset, arrival, departure, language]);
  useEffect(() => {
    let active = true;
    queueMicrotask(() => {
      if (active) void load();
    });
    return () => {
      active = false;
    };
  }, [load]);
  useEffect(() => {
    const { data } = db.auth.onAuthStateChange((_event, session) => {
      setSignedIn(Boolean(session?.user));
      setRequests([]);
      generation.current++;
      setTimeout(() => void load(), 0);
    });
    return () => data.subscription.unsubscribe();
  }, [db, load]);
  async function enquire(
    event: FormEvent<HTMLFormElement>,
    lodgeId: string,
    apply = false,
  ) {
    event.preventDefault();
    const f = new FormData(event.currentTarget);
    setBusy(true);
    setMessage("");
    try {
      const r = apply
        ? await db.rpc("lodge_command", {
            p_lodge: lodgeId,
            p_action: "apply_access",
            p_data: { notes: f.get("notes") },
          })
        : await db.rpc("lodge_enquire", {
            p_lodge: lodgeId,
            p_data: {
              arrival: f.get("arrival"),
              departure: f.get("departure"),
              guests: Number(f.get("guests")),
              room_type_id: f.get("room_type_id"),
              message: f.get("message"),
              contact_phone: f.get("contact_phone"),
            },
          });
      if (r.error) throw r.error;
      if (!apply) await load();
      setMessage(
        apply
          ? "Application submitted for lodge-owner review."
          : "Enquiry sent. This is not a confirmed reservation. The lodge will contact you directly.",
      );
    } catch (e) {
      setMessage(lodgeUserMessage(e, language));
    } finally {
      setBusy(false);
    }
  }
  const list = Array.isArray(data.rows) ? (data.rows as LodgeRow[]) : [];
  const searchForm = (
    <form
      className="mb-6 grid gap-3 rounded-2xl bg-white p-5 sm:grid-cols-2"
      onSubmit={(e) => {
        e.preventDefault();
        const f = new FormData(e.currentTarget);
        setSearch(String(f.get("q")));
        setArrival(String(f.get("arrival")));
        setDeparture(String(f.get("departure")));
        setOffset(0);
      }}
    >
      {!id && (
        <label className="grid gap-2">
          <UiText text="Search by lodge, location or facilities" />
          <input
            className="rounded-xl border p-3"
            name="q"
            maxLength={160}
            defaultValue={search}
          />
        </label>
      )}
      {!id && (
        <div>
          <UiText text="Location (optional)" />
          <EventLocationFields
            value={location}
            onChange={(v) => {
              setLocation(v);
              setOffset(0);
            }}
          />
        </div>
      )}
      <label className="grid gap-2">
        <UiText text="Arrival" />
        <input
          className="rounded-xl border p-3"
          name="arrival"
          type="date"
          defaultValue={arrival}
        />
      </label>
      <label className="grid gap-2">
        <UiText text="Departure" />
        <input
          className="rounded-xl border p-3"
          name="departure"
          type="date"
          defaultValue={departure}
        />
      </label>
      <button className="btn btn-success">
        <UiText text="Search" />
      </button>
    </form>
  );
  return (
    <main className="mx-auto max-w-6xl px-4 py-8 text-[#17323a]">
      <header className="mb-6 flex flex-wrap items-center justify-between gap-3">
        <h1 className="font-heading text-3xl font-bold">
          <UiText
            text={id && list[0] ? String(list[0].name) : "Lodges & Guesthouses"}
          />
        </h1>
        {!id && (
          <Link href="/manage/lodges" className="btn btn-outline">
            <UiText text="Manage your lodge" />
          </Link>
        )}
      </header>
      {!id && (
        <p className="mb-5">
          <UiText text="Browse anywhere. Contact the lodge directly to arrange your stay and payment." />
        </p>
      )}
      {!id && searchForm}

      {message && (
        <p role="status" className="mb-5 rounded-xl border bg-white p-4">
          <UiText text={message} />
        </p>
      )}
      {loading ? (
        <NavigationIndicator inline />
      ) : !list.length ? (
        <p className="rounded-2xl bg-white p-6">
          <UiText text="No published lodges match this search." />
        </p>
      ) : (
        <div className={id ? "grid gap-6" : "grid gap-5 sm:grid-cols-2"}>
          {list.map((l) => {
            let phone = String(l.phone ?? "").replace(/\D/g, "");
            if (phone.startsWith("0")) phone = "255" + phone.slice(1);
            const photos = Array.isArray(l.photos)
              ? (l.photos as string[])
              : [];
            return (
              <article
                key={String(l.id)}
                className="overflow-hidden rounded-3xl border bg-white"
              >
                {photos.length > 0 && (
                  <div className={id ? "flex snap-x overflow-x-auto" : "h-56"}>
                    {(id ? photos : photos.slice(0, 1)).map((path) => (
                      <div
                        key={path}
                        className={
                          id
                            ? "aspect-[4/5] w-full shrink-0 snap-center bg-[#173f46] sm:aspect-[4/3]"
                            : "h-full bg-[#173f46]"
                        }
                      >
                        {images[path] && (
                          <DirectMediaImage
                            src={images[path]}
                            alt={String(l.name)}
                            className="h-full w-full object-contain"
                            sizes={
                              id ? "100vw" : "(min-width:768px) 50vw, 100vw"
                            }
                          />
                        )}
                      </div>
                    ))}
                  </div>
                )}
                <div className="grid gap-3 p-5">
                  {!id && (
                    <h2 className="text-2xl font-bold">{String(l.name)}</h2>
                  )}
                  {id && (
                    <p className="text-sm">
                      <UiText text="Dates use the lodge timezone" />:{" "}
                      {String(l.timezone)}.{" "}
                      <UiText text="Departure date is not included." />
                    </p>
                  )}
                  <p>{String(l.location_label)}</p>
                  <p>
                    <UiText text="Verified lodge" />
                  </p>
                  {id && (
                    <p className="whitespace-pre-line">
                      {String(l.description)}
                    </p>
                  )}
                  <p>
                    {Array.isArray(l.facilities)
                      ? l.facilities.join(" · ")
                      : ""}
                  </p>
                  {id && (
                    <>
                      <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
                        {Object.entries((l.room_counts ?? {}) as LodgeRow)
                          .filter(([, value]) => value !== null)
                          .map(([key, value]) => (
                            <div
                              key={key}
                              className="rounded-xl bg-[#eef5f2] p-3"
                            >
                              <p className="text-sm">
                                <UiText
                                  text={
                                    (
                                      {
                                        total_active: "Active rooms",
                                        occupied: "Occupied now",
                                        ready_now: "Ready now",
                                        cleaning: "Cleaning",
                                        maintenance: "Maintenance",
                                        selected_dates_available:
                                          "Rooms available for selected dates",
                                      } as Record<string, string>
                                    )[key] ?? key
                                  }
                                />
                              </p>
                              <strong className="text-2xl">
                                {String(value)}
                              </strong>
                            </div>
                          ))}
                      </div>
                      <p>
                        <UiText text="Check-in policy" />:{" "}
                        {String(l.check_in_policy || "Confirm with the lodge.")}
                      </p>
                      <p>
                        <UiText text="Check-out policy" />:{" "}
                        {String(
                          l.check_out_policy || "Confirm with the lodge.",
                        )}
                      </p>
                      {searchForm}
                    </>
                  )}
                  <div
                    className={id ? "grid gap-5 md:grid-cols-2" : "grid gap-3"}
                  >
                    {(Array.isArray(l.room_types)
                      ? (l.room_types as LodgeRow[])
                      : []
                    ).map((t) => (
                      <div
                        key={String(t.room_type) + String(t.currency)}
                        className="rounded-2xl bg-[#eef5f2] p-4"
                      >
                        {id && (
                          <div className="mb-4 aspect-[4/3] overflow-hidden rounded-xl bg-white">
                            {t.main_image && images[String(t.main_image)] ? (
                              <DirectMediaImage
                                src={images[String(t.main_image)]}
                                alt={`${String(t.room_type)} — representative room-type photograph`}
                                className="h-full w-full object-cover"
                                sizes="(min-width:768px) 50vw, 100vw"
                              />
                            ) : (
                              <div className="flex h-full items-center justify-center">
                                <UiText text="No authorized photograph available" />
                              </div>
                            )}
                          </div>
                        )}
                        <h3 className="text-xl font-bold">
                          {String(t.room_type)}
                        </h3>
                        <p className="my-2">{String(t.description ?? "")}</p>
                        <p className="text-sm">
                          {Array.isArray(t.facilities)
                            ? t.facilities.join(" · ")
                            : ""}
                        </p>
                        <p className="text-xs">
                          <UiText text="Representative room-type photograph; the assigned room may differ." />
                        </p>
                        <p>
                          {String(t.currency)} {String(t.from_price)} /{" "}
                          <UiText text="night" /> · <UiText text="Up to" />{" "}
                          {String(t.max_occupancy)} <UiText text="guests" />
                        </p>
                        {t.available_rooms !== null &&
                        t.available_rooms !== undefined ? (
                          <p>
                            <UiText text="Rooms available for selected dates" />
                            : {String(t.available_rooms)}
                          </p>
                        ) : (
                          <p>
                            <UiText text="Ask the lodge to confirm availability." />
                          </p>
                        )}
                        {id && (
                          <button
                            type="button"
                            className="btn btn-success mt-3"
                            onClick={() => {
                              setRequestedType(String(t.id));
                              document
                                .getElementById("lodge-request")
                                ?.scrollIntoView({ behavior: "smooth" });
                            }}
                          >
                            <UiText text="Request reservation" />
                          </button>
                        )}
                      </div>
                    ))}
                  </div>
                  {arrival && l.publish_availability === true && (
                    <p className="text-sm">
                      <UiText text="Availability checked against lodge reservations. It may change before confirmation." />{" "}
                      {String(data.availability_checked_at ?? "")}
                    </p>
                  )}
                  <div className="flex flex-wrap gap-2">
                    {!id && (
                      <Link
                        href={`/lodges/${l.id}`}
                        className="btn btn-success"
                      >
                        <UiText text="View lodge" />
                      </Link>
                    )}
                    {l.phone != null && (
                      <a
                        className="btn btn-outline"
                        href={`tel:${String(l.phone)}`}
                      >
                        {String(l.phone)}
                      </a>
                    )}
                    {l.phone != null && (
                      <a
                        className="btn btn-outline"
                        href={`https://wa.me/${phone}`}
                        target="_blank"
                        rel="noopener noreferrer"
                      >
                        WhatsApp
                      </a>
                    )}
                  </div>
                  {id && (
                    <>
                      <section
                        id="lodge-request"
                        className="mt-4 scroll-mt-20 border-t pt-5"
                      >
                        <h3 className="text-xl font-bold">
                          <UiText text="Send a reservation enquiry" />
                        </h3>
                        <p className="my-3 text-sm">
                          <UiText
                            text={
                              signedIn
                                ? "The lodge confirms your reservation directly; payment is arranged with the lodge."
                                : "Sign in to send an enquiry. The lodge confirms your reservation directly; no KODIMALI checkout is required."
                            }
                          />
                        </p>
                        {!signedIn && (
                          <Link href="/account" className="btn btn-outline">
                            <UiText text="Sign in" />
                          </Link>
                        )}
                        <form
                          className="mt-3 grid gap-3 sm:grid-cols-2"
                          onSubmit={(e) => void enquire(e, String(l.id))}
                        >
                          <label className="grid gap-1">
                            <UiText text="Room type" />
                            <select
                              required
                              name="room_type_id"
                              className="rounded-xl border p-3"
                              value={
                                requestedType ||
                                String(
                                  ((l.room_types as LodgeRow[]) ?? [])[0]?.id ??
                                    "",
                                )
                              }
                              onChange={(e) => setRequestedType(e.target.value)}
                            >
                              {(Array.isArray(l.room_types)
                                ? (l.room_types as LodgeRow[])
                                : []
                              ).map((t) => (
                                <option key={String(t.id)} value={String(t.id)}>
                                  {String(t.room_type)} / {String(t.currency)}{" "}
                                  {String(t.from_price)}
                                </option>
                              ))}
                            </select>
                          </label>
                          {[
                            { name: "arrival", text: "Arrival", type: "date" },
                            {
                              name: "departure",
                              text: "Departure",
                              type: "date",
                            },
                            { name: "guests", text: "Guests", type: "number" },
                            {
                              name: "contact_phone",
                              text: "Contact phone",
                              type: "tel",
                            },
                            {
                              name: "message",
                              text: "Enquiry details",
                              type: "text",
                            },
                          ].map((f) => (
                            <label key={f.name} className="grid gap-1">
                              <UiText text={f.text} />
                              <input
                                className="rounded-xl border p-3"
                                name={f.name}
                                type={f.type}
                                min={f.type === "number" ? 1 : undefined}
                                max={f.type === "number" ? 100 : undefined}
                                defaultValue={
                                  f.name === "guests"
                                    ? 1
                                    : f.name === "arrival"
                                      ? arrival
                                      : f.name === "departure"
                                        ? departure
                                        : ""
                                }
                                maxLength={2000}
                                required
                              />
                            </label>
                          ))}
                          <button
                            disabled={busy || !signedIn}
                            className="btn btn-success"
                          >
                            <UiText text="Send enquiry" />
                          </button>
                        </form>
                      </section>
                      <section className="mt-4 border-t pt-5">
                        <h3 className="font-bold">
                          <UiText text="Apply to manage this lodge" />
                        </h3>
                        <form
                          onSubmit={(e) => void enquire(e, String(l.id), true)}
                          className="mt-3 grid gap-3"
                        >
                          <label className="grid gap-1">
                            <UiText text="Explain your authority to manage this lodge" />
                            <textarea
                              className="rounded-xl border p-3"
                              name="notes"
                              minLength={10}
                              maxLength={2000}
                              required
                            />
                          </label>
                          <button disabled={busy} className="btn btn-outline">
                            <UiText text="Submit application" />
                          </button>
                        </form>
                      </section>
                    </>
                  )}
                </div>
              </article>
            );
          })}
        </div>
      )}
      {requests.map((r) => (
        <article
          key={String(r.id)}
          className="mb-4 rounded-2xl border bg-white p-4"
        >
          <h2 className="font-bold">{String(r.room_type)}</h2>
          <p>
            {String(r.arrival)} → {String(r.departure)}
          </p>
          <p>
            <UiText
              text={
                r.status === "cancelled"
                  ? "Reservation cancelled"
                  : r.status === "closed"
                    ? "Request closed"
                    : r.confirmed
                      ? "Reservation confirmed"
                      : "Awaiting lodge confirmation"
              }
            />{" "}
            / {String(r.status)}
          </p>
        </article>
      ))}
      {requests.length > 0 && (
        <button className="btn btn-outline mb-4" onClick={() => void load()}>
          <UiText text="Refresh requests" />
        </button>
      )}
      {!id && (
        <div className="mt-5 flex justify-between">
          <button
            disabled={offset === 0}
            className="btn btn-outline"
            onClick={() => setOffset(Math.max(0, offset - 20))}
          >
            <UiText text="Previous" />
          </button>
          <button
            disabled={offset + 20 >= Number(data.total ?? 0)}
            className="btn btn-outline"
            onClick={() => setOffset(offset + 20)}
          >
            <UiText text="Next" />
          </button>
        </div>
      )}
    </main>
  );
}
