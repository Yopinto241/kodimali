"use client";
import { LodgePhotos } from "@/components/lodge-photos";
import Link from "next/link";
import {
  useCallback,
  useEffect,
  useState,
  useRef,
  type FormEvent,
} from "react";
import { getLodgeClient } from "@/lib/lodge-client";
import { lodgeUserMessage } from "@/lib/lodge-errors";
import { useLanguage } from "@/components/language-provider";
import { UiText } from "@/components/ui-text";
import { EventLocationFields } from "@/components/event-location-fields";
import {
  useNavigate,
  NavigationIndicator,
} from "@/components/navigation-progress";
import { prepareListingImage } from "@/lib/listing-image";
import {
  lodgeForms,
  lodgeFormTitles,
  lodgeFormData,
  lodgePermissions,
  lodgePermissionLabels,
  lodgeSections,
  lodgeSectionPermission,
  type LodgeRow,
} from "@/lib/lodge-forms";
const rows = (x: unknown): LodgeRow[] => (Array.isArray(x) ? x : []);
const label = (x: unknown) => String(x ?? "").replaceAll("_", " ");
function LodgeActionButton({
  text,
  action,
  initial,
  busy,
  onOpen,
}: {
  text: string;
  action: string;
  initial: LodgeRow;
  busy: boolean;
  onOpen: (action: string, initial: LodgeRow) => Promise<void>;
}) {
  return (
    <button
      className="btn btn-outline"
      disabled={busy}
      onClick={() => void onOpen(action, initial)}
    >
      <UiText text={text} />
    </button>
  );
}
export function LodgeWorkspace({
  lodgeId,
  section = "dashboard",
}: {
  lodgeId?: string;
  section?: string;
}) {
  const db = getLodgeClient(),
    { language } = useLanguage();
  const navigate = useNavigate();
  const generation = useRef(0),
    lastUser = useRef<string | null | undefined>(undefined);
  const [data, setData] = useState<LodgeRow>({}),
    [loading, setLoading] = useState(true),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false);
  const [query, setQuery] = useState(""),
    [roomType, setRoomType] = useState("");
  const [offset, setOffset] = useState(0),
    [start, setStart] = useState(""),
    [end, setEnd] = useState("");
  const [editor, setEditor] = useState<{
    action: string;
    initial: LodgeRow;
    requestId?: string;
  } | null>(
    section === "register" ? { action: "register", initial: {} } : null,
  );
  const [rooms, setRooms] = useState<LodgeRow[]>([]),
    [bookings, setBookings] = useState<LodgeRow[]>([]),
    [location, setLocation] = useState("");
  const [photos, setPhotos] = useState<string[]>([]),
    [formError, setFormError] = useState("");
  const permissions = Array.isArray(data.permissions)
    ? (data.permissions as string[])
    : [];
  const can = (p: string) =>
    permissions.includes("*") || permissions.includes(p);
  const lodge = (data.lodge ?? {}) as LodgeRow;
  const load = useCallback(async () => {
    const request = ++generation.current;
    setLoading(true);
    setError("");
    try {
      const response = await db.rpc(
        "lodge_workspace",
        lodgeId
          ? {
              p_lodge: lodgeId,
              p_section: section,
              p_offset: offset,
              p_query: query,
              p_room_type: roomType,
              p_limit: 30,
              p_start: start || null,
              p_end: end || null,
            }
          : {},
      );
      if (response.error) throw response.error;
      if (request !== generation.current) return;
      setData(response.data as LodgeRow);
    } catch (e) {
      if (request === generation.current)
        setError(lodgeUserMessage(e, language));
    } finally {
      if (request === generation.current) setLoading(false);
    }
  }, [db, lodgeId, section, offset, start, end, language, query, roomType]);
  const [user, setUser] = useState<string | null | undefined>(undefined);
  useEffect(() => {
    const { data: subscription } = db.auth.onAuthStateChange(
      (_event, session) => {
        const next = session?.user.id ?? null;
        if (next !== lastUser.current) {
          lastUser.current = next;
          generation.current++;
          setData({});
          setEditor(null);
          setRooms([]);
          setBookings([]);
          setPhotos([]);
          setFormError("");
          setUser(next);
        }
      },
    );
    return () => subscription.subscription.unsubscribe();
  }, [db]);
  useEffect(() => {
    let active = true;
    queueMicrotask(() => {
      if (active && user !== undefined) {
        setData({});
        setEditor(
          section === "register" && user
            ? { action: "register", initial: {} }
            : null,
        );
        void load();
      }
    });
    return () => {
      active = false;
    };
  }, [load, user, section]);
  async function command(
    action: string,
    body: LodgeRow = {},
    target = lodgeId,
  ) {
    setBusy(true);
    setError("");
    try {
      const r = await db.rpc("lodge_command", {
        p_lodge: target,
        p_action: action,
        p_data: body,
      });
      if (r.error) throw r.error;
      await load();
    } catch (e) {
      setError(lodgeUserMessage(e, language));
    } finally {
      setBusy(false);
    }
  }
  async function open(action: string, initial: LodgeRow = {}) {
    const request = generation.current;
    setFormError("");
    setLocation(String(initial.location_id ?? ""));
    setPhotos(
      action === "save_room_type"
        ? initial.main_image
          ? [String(initial.main_image)]
          : []
        : Array.isArray(initial.photos)
          ? (initial.photos as string[])
          : [],
    );
    setEditor({ action, initial, requestId: crypto.randomUUID() });
    if (
      lodgeId &&
      [
        "reserve",
        "block_room",
        "reservation_update",
        "record_payment",
        "save_room",
      ].includes(action)
    ) {
      const r = await db.rpc("lodge_workspace", {
        p_lodge: lodgeId,
        p_section:
          action === "save_room"
            ? "room-types"
            : action === "record_payment"
              ? "reservations"
              : "rooms",
        p_limit: 100,
        p_start: start || null,
        p_end: end || null,
      });
      if (request !== generation.current) return;
      if (r.error) {
        setFormError(lodgeUserMessage(r.error, language));
        return;
      }
      const d = r.data as LodgeRow;
      if (action === "record_payment") setBookings(rows(d.rows));
      else
        setRooms(
          rows(d.rows).filter(
            (r) =>
              action !== "reservation_update" ||
              !initial.accepted_at ||
              r.room_type_id === initial.room_type_id,
          ),
        );
    }
  }
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!editor) return;
    const form = event.currentTarget;
    const action = editor.action;
    setBusy(true);
    setFormError("");
    try {
      const body = lodgeFormData(form, action, editor.initial);
      body.request_id = editor.requestId ?? crypto.randomUUID();
      if (action === "settings") body.photos = photos;
      if (action === "save_room_type") body.main_image = photos[0] ?? null;
      const r =
        action === "register"
          ? await db.rpc("lodge_register", { p_data: body })
          : await db.rpc("lodge_command", {
              p_lodge: lodgeId,
              p_action: action,
              p_data: body,
            });
      if (r.error) throw r.error;
      if (action === "register") {
        navigate(`/manage/lodges/${r.data}/dashboard`);
        return;
      }
      setEditor(null);
      await load();
    } catch (e) {
      setFormError(lodgeUserMessage(e, language));
    } finally {
      setBusy(false);
    }
  }
  async function upload(files: FileList | null) {
    if (!files || !lodgeId) return;
    setBusy(true);
    setFormError("");
    try {
      if (
        files.length + photos.length >
        (editor?.action === "save_room_type" ? 1 : 20)
      )
        throw new Error("Choose up to 20 photos.");
      const paths: string[] = [];
      for (const file of Array.from(files)) {
        const blob = await prepareListingImage(file);
        const path = `${lodgeId}/photos/${crypto.randomUUID()}.jpg`;
        const r = await db.storage
          .from("lodge-media")
          .upload(path, blob, {
            contentType: "image/jpeg",
            cacheControl: "86400",
            upsert: false,
          });
        if (r.error) throw r.error;
        paths.push(path);
      }
      setPhotos((old) => [...old, ...paths]);
    } catch (e) {
      setFormError(lodgeUserMessage(e, language));
    } finally {
      setBusy(false);
    }
  }
  const actionButton = (
    text: string,
    action: string,
    initial: LodgeRow = {},
  ) => (
    <LodgeActionButton
      text={text}
      action={action}
      initial={initial}
      busy={busy}
      onOpen={open}
    />
  );
  const operation = (text: string, action: string, body: LodgeRow) => (
    <button
      className="btn btn-outline"
      disabled={busy}
      onClick={() => void command(action, body)}
    >
      <UiText text={text} />
    </button>
  );
  return (
    <main className="mx-auto max-w-7xl px-4 py-6 text-[#17323a]">
      <header className="mb-6 flex flex-wrap items-center justify-between gap-3">
        <div>
          <Link href="/manage/lodges" className="font-bold">
            KODIMALI / <UiText text="Lodge workspace" />
          </Link>
          <h1 className="mt-3 font-heading text-3xl font-bold">
            {String(
              lodge.name ??
                (lodgeId ? "Lodge workspace" : "Lodges & Guesthouses"),
            )}
          </h1>
        </div>
        <Link href="/manage" className="btn btn-outline">
          <UiText text="Manage" />
        </Link>
      </header>
      <p className="mb-5 rounded-2xl bg-white p-4 text-sm">
        <UiText text="Reservations and payments are managed directly by the lodge. KODIMALI does not collect or verify these payments." />
      </p>
      {error && (
        <p role="alert" className="mb-4 rounded-xl bg-red-50 p-4 text-red-900">
          {error}{" "}
          <button onClick={() => void load()}>
            <UiText text="Retry" />
          </button>{" "}
          <Link href="/account">
            <UiText text="Sign in" />
          </Link>
        </p>
      )}
      {loading ? (
        <NavigationIndicator />
      ) : (
        !error && (
          <>
            {!lodgeId ? (
              <>
                <div className="mb-5 flex flex-wrap gap-3">
                  <Link
                    href="/manage/lodges/register"
                    className="btn btn-success"
                  >
                    <UiText text="Register a lodge" />
                  </Link>
                  <Link href="/lodges" className="btn btn-outline">
                    <UiText text="Browse lodges" />
                  </Link>
                </div>
                <div className="grid gap-4 md:grid-cols-2">
                  {rows(data.lodges).map((row) => (
                    <Link
                      className="rounded-2xl border bg-white p-6"
                      key={String(row.id)}
                      href={`/manage/lodges/${row.id}/dashboard`}
                    >
                      <h2 className="text-xl font-bold">{String(row.name)}</h2>
                      <p>{String(row.location_label)}</p>
                      <p>
                        <UiText text={label(row.verification_status)} />
                      </p>
                    </Link>
                  ))}
                </div>
                {!rows(data.lodges).length && (
                  <p className="my-6">
                    <UiText text="Register your first lodge or accept an invitation below." />
                  </p>
                )}
                {rows(data.invitations).map((row) => (
                  <div
                    key={String(row.id)}
                    className="my-4 rounded-2xl bg-white p-5"
                  >
                    <h2>
                      {String(row.name)} / <UiText text={label(row.role)} />
                    </h2>
                    <button
                      disabled={busy}
                      className="btn btn-success"
                      onClick={() =>
                        void command(
                          "accept_invitation",
                          { id: row.id },
                          String(row.lodge_id),
                        )
                      }
                    >
                      <UiText text="Accept invitation" />
                    </button>
                  </div>
                ))}
              </>
            ) : (
              <>
                <nav
                  aria-label="Lodge pages"
                  className="mb-5 flex gap-2 overflow-x-auto pb-3"
                >
                  {lodgeSections
                    .filter(
                      (s) =>
                        !lodgeSectionPermission[s] ||
                        can(lodgeSectionPermission[s]),
                    )
                    .map((s) => (
                      <Link
                        aria-current={s === section ? "page" : undefined}
                        key={s}
                        href={`/manage/lodges/${lodgeId}/${s}`}
                        className={`shrink-0 rounded-full px-4 py-3 font-semibold ${s === section ? "bg-[#0e7771] text-white" : "bg-white text-[#17323a]"}`}
                      >
                        <UiText
                          text={(
                            s.charAt(0).toUpperCase() + s.slice(1)
                          ).replaceAll("-", " ")}
                        />
                      </Link>
                    ))}
                </nav>
                {[
                  "room-types",
                  "calendar",
                  "reservations",
                  "reports",
                  "dashboard",
                ].includes(section) && (
                  <form
                    className="mb-5 flex flex-wrap items-end gap-3"
                    onSubmit={(e) => {
                      e.preventDefault();
                      const d = new FormData(e.currentTarget);
                      setStart(String(d.get("start")));
                      setEnd(String(d.get("end")));
                      setOffset(0);
                    }}
                  >
                    <label>
                      <UiText text="From" />
                      <input
                        className="block rounded-xl border bg-white p-3"
                        name="start"
                        type="date"
                        defaultValue={String(data.start ?? "")}
                        required
                      />
                    </label>
                    <label>
                      <UiText text="To" />
                      <input
                        className="block rounded-xl border bg-white p-3"
                        name="end"
                        type="date"
                        defaultValue={String(data.end ?? "")}
                        required
                      />
                    </label>
                    <button className="btn btn-outline">
                      <UiText text="Apply dates" />
                    </button>
                    <span className="text-sm">{String(lodge.timezone)}</span>
                  </form>
                )}
                {[
                  "rooms",
                  "calendar",
                  "reservations",
                  "guests",
                  "payments",
                ].includes(section) && (
                  <form
                    className="mb-5 flex flex-wrap gap-3"
                    onSubmit={(e) => {
                      e.preventDefault();
                      const f = new FormData(e.currentTarget);
                      setQuery(String(f.get("query") ?? ""));
                      setRoomType(String(f.get("room_type") ?? ""));
                      setOffset(0);
                    }}
                  >
                    <label>
                      <UiText text="Search" />
                      <input
                        name="query"
                        className="block rounded-xl border bg-white p-3"
                        defaultValue={query}
                        maxLength={160}
                      />
                    </label>
                    {["rooms", "calendar"].includes(section) && (
                      <label>
                        <UiText text="Room type" />
                        <input
                          name="room_type"
                          className="block rounded-xl border bg-white p-3"
                          defaultValue={roomType}
                          maxLength={100}
                        />
                      </label>
                    )}
                    <button className="btn btn-outline">
                      <UiText text="Search" />
                    </button>
                  </form>
                )}
                <div className="mb-5 flex flex-wrap gap-3">
                  {section === "room-types" &&
                    can("rooms.write") &&
                    actionButton("Add room type", "save_room_type", {
                      active: true,
                      currency: "TZS",
                      max_occupancy: 2,
                    })}
                  {section === "rooms" &&
                    can("rooms.write") &&
                    actionButton("Add room", "save_room", {
                      active: true,
                      currency: "TZS",
                      max_occupancy: 2,
                    })}
                  {section === "reservations" &&
                    can("reservations.write") &&
                    actionButton("New reservation", "reserve", {
                      guests: 1,
                      status: "confirmed",
                      channel: "walk_in",
                    })}
                  {["rooms", "calendar", "reservations"].includes(section) &&
                    can("reservations.write") &&
                    actionButton("Block room dates", "block_room")}
                  {section === "payments" &&
                    can("payments.write") &&
                    actionButton("Record lodge payment", "record_payment")}
                  {section === "staff" &&
                    can("staff.manage") &&
                    actionButton("Invite staff", "invite", {
                      role: "receptionist",
                    })}
                  {section === "settings" &&
                    can("settings.write") &&
                    actionButton("Edit lodge settings", "settings", lodge)}
                  {section === "settings" &&
                    data.super_admin === true &&
                    !!data.lodge && (
                      <>
                        <button
                          className="btn btn-outline"
                          disabled={busy}
                          onClick={() =>
                            void command("review", {
                              approved: true,
                              notes: "Reviewed lodge application",
                            })
                          }
                        >
                          <UiText text="Super Admin: approve publication" />
                        </button>
                        <button
                          className="btn btn-outline"
                          disabled={busy}
                          onClick={() =>
                            void command("review", {
                              approved: false,
                              notes: "Publication withdrawn after review",
                            })
                          }
                        >
                          <UiText text="Super Admin: withdraw publication" />
                        </button>
                      </>
                    )}
                </div>
                {section === "settings" && (
                  <article className="rounded-2xl bg-white p-6">
                    <LodgePhotos paths={lodge.photos} />
                    <p>
                      <UiText text="Verification status" />:{" "}
                      <UiText text={label(lodge.verification_status)} />
                    </p>
                    <p>
                      <UiText text="Public location" />:{" "}
                      {String(lodge.location_label)}
                    </p>
                    <p>
                      {String(lodge.phone)} / {String(lodge.email ?? "")}
                    </p>
                    <p>{String(lodge.description)}</p>
                    <p>
                      {Array.isArray(lodge.facilities)
                        ? lodge.facilities.join(" · ")
                        : ""}
                    </p>
                    <p>{String(lodge.timezone)}</p>
                    <p>
                      <UiText text="Publish date-based availability" />:{" "}
                      {String(lodge.publish_availability)}
                    </p>
                  </article>
                )}
                {!!data.stats && (
                  <div className="grid grid-cols-2 gap-3 md:grid-cols-3">
                    {Object.entries(data.stats as LodgeRow).map(
                      ([key, value]) => (
                        <article key={key} className="rounded-2xl bg-white p-5">
                          <UiText text={label(key)} />
                          <p className="text-3xl font-bold">{String(value)}</p>
                        </article>
                      ),
                    )}
                  </div>
                )}
                {["dashboard", "reports"].includes(section) && (
                  <div className="my-5 grid gap-3 sm:grid-cols-3">
                    {["arrivals", "departures", "pending"]
                      .filter((k) => data[k] !== undefined)
                      .map((k) => (
                        <article key={k} className="rounded-2xl bg-white p-5">
                          <UiText text={k} />
                          <p className="text-2xl font-bold">
                            {String(data[k])}
                          </p>
                        </article>
                      ))}
                    {data.capacity_room_nights !== undefined && (
                      <article className="rounded-2xl bg-white p-5">
                        <UiText text="Occupancy" />
                        <p className="text-2xl font-bold">
                          {Number(data.capacity_room_nights) > 0
                            ? (
                                (100 * Number(data.occupied_room_nights)) /
                                Number(data.capacity_room_nights)
                              ).toFixed(1)
                            : "0"}
                          %
                        </p>
                        <p>
                          {String(data.occupied_room_nights)} /{" "}
                          {String(data.capacity_room_nights)}{" "}
                          <UiText text="room nights / registered room capacity" />
                        </p>
                      </article>
                    )}
                    {rows(data.revenue).map((r) => (
                      <article
                        key={String(r.currency)}
                        className="rounded-2xl bg-white p-5"
                      >
                        <UiText text="Net lodge payments recorded" />
                        <p className="text-2xl font-bold">
                          {String(r.currency)} {String(r.net_recorded)}
                        </p>
                      </article>
                    ))}
                  </div>
                )}
                {section === "calendar" && (
                  <div className="overflow-x-auto rounded-2xl border bg-white">
                    <table className="w-full min-w-[600px] text-left">
                      <caption className="p-4 text-left">
                        <UiText text="Room condition and date-based reservations are separate." />
                      </caption>
                      <thead>
                        <tr>
                          <th className="p-3">
                            <UiText text="Room" />
                          </th>
                          <th>
                            <UiText text="Room type" />
                          </th>
                          <th>
                            <UiText text="Condition" />
                          </th>
                          <th>
                            <UiText text="Reserved dates" />
                          </th>
                        </tr>
                      </thead>
                      <tbody>
                        {rows(data.rows).map((r) => (
                          <tr key={String(r.id)} className="border-t">
                            <td className="p-3 font-bold">{String(r.code)}</td>
                            <td>{String(r.room_type)}</td>
                            <td>
                              <UiText text={label(r.condition)} />
                            </td>
                            <td>
                              {rows(data.stays)
                                .filter((b) => b.room_id === r.id)
                                .map((b) => (
                                  <p
                                    key={String(b.id)}
                                    className="my-2 rounded-lg bg-teal-50 p-2"
                                  >
                                    {String(b.arrival)} → {String(b.departure)}{" "}
                                    / <UiText text={label(b.status)} />
                                  </p>
                                ))}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
                {section !== "calendar" && (
                  <div className="grid gap-4 md:grid-cols-2">
                    {rows(data.rows).map((row) => (
                      <article
                        className="rounded-2xl border bg-white p-5"
                        key={String(row.id ?? row.profile_id)}
                      >
                        {section === "room-types" ? (
                          <>
                            <LodgePhotos
                              paths={
                                row.main_image ? [String(row.main_image)] : []
                              }
                            />
                            <h2 className="text-xl font-bold">
                              {String(row.name)}
                            </h2>
                            <p>{String(row.description)}</p>
                            <p>
                              {String(row.currency)} {String(row.nightly_rate)}{" "}
                              / <UiText text="night" />
                            </p>
                            <p>
                              <UiText text="Active rooms" />:{" "}
                              {String(row.total_rooms)} /{" "}
                              <UiText text="Rooms available for selected dates" />
                              : {String(row.available_rooms)}
                            </p>
                            <p>
                              <UiText text="Occupied now" />:{" "}
                              {String(row.occupied_rooms)} /{" "}
                              <UiText text="Ready now" />:{" "}
                              {String(row.ready_now)}
                            </p>
                            {can("rooms.write") &&
                              actionButton(
                                "Edit room type",
                                "save_room_type",
                                row,
                              )}
                          </>
                        ) : section === "rooms" ? (
                          <>
                            <LodgePhotos paths={row.photos} />
                            <h2 className="text-xl font-bold">
                              {String(row.code)} / {String(row.room_type)}
                            </h2>
                            <p>
                              {String(row.beds)} · {String(row.max_occupancy)}{" "}
                              <UiText text="guests" />
                            </p>
                            <p>
                              {String(row.currency)} {String(row.nightly_rate)}{" "}
                              / <UiText text="night" />
                            </p>
                            <p>
                              <UiText text={label(row.condition)} /> /{" "}
                              <UiText
                                text={row.active ? "Active" : "Inactive"}
                              />
                            </p>
                            <p>{String(row.maintenance_notes ?? "")}</p>
                            <div className="mt-3 flex flex-wrap gap-2">
                              {can("rooms.write") &&
                                actionButton("Edit room", "save_room", row)}
                              {(can("rooms.write") ||
                                can("rooms.condition")) && (
                                <select
                                  aria-label="Room condition"
                                  className="rounded-xl border p-2"
                                  value={String(row.condition)}
                                  disabled={
                                    busy || row.condition === "occupied"
                                  }
                                  onChange={(e) =>
                                    void command("room_condition", {
                                      id: row.id,
                                      condition: e.target.value,
                                    })
                                  }
                                >
                                  {[
                                    "ready",
                                    "occupied",
                                    "cleaning",
                                    "maintenance",
                                    "out_of_service",
                                  ].map((s) => (
                                    <option key={s} value={s}>
                                      {label(s)}
                                    </option>
                                  ))}
                                </select>
                              )}
                            </div>
                          </>
                        ) : section === "reservations" ? (
                          <>
                            <h2 className="text-xl font-bold">
                              {String(row.code)} /{" "}
                              {String(row.full_name ?? "Room block")}
                            </h2>
                            <p>
                              {String(row.arrival)} → {String(row.departure)}
                            </p>
                            <p>
                              <UiText text={label(row.status)} /> /{" "}
                              <UiText text={label(row.channel)} />
                            </p>
                            <p>{String(row.phone ?? "")}</p>
                            <p>
                              {String(row.currency)} {String(row.total_amount)}{" "}
                              · <UiText text="Outstanding balance" />:{" "}
                              {row.paid === null
                                ? "—"
                                : Number(row.total_amount) - Number(row.paid)}
                            </p>
                            <div className="mt-3 flex flex-wrap gap-2">
                              {can("reservations.write") && (
                                <>
                                  {["pending", "confirmed", "blocked"].includes(
                                    String(row.status),
                                  ) && (
                                    <>
                                      {actionButton(
                                        "Modify reservation",
                                        "reservation_update",
                                        row,
                                      )}
                                      {actionButton(
                                        "Cancel reservation",
                                        "cancel",
                                        row,
                                      )}
                                    </>
                                  )}
                                  {row.status === "confirmed" &&
                                    operation("Check in", "check_in", {
                                      id: row.id,
                                    })}
                                  {row.status === "checked_in" &&
                                    operation("Check out", "check_out", {
                                      id: row.id,
                                    })}
                                </>
                              )}
                              {can("payments.write") &&
                                row.status !== "blocked" &&
                                actionButton(
                                  "Record lodge payment",
                                  "record_payment",
                                  {
                                    reservation_id: row.id,
                                    code: row.code,
                                    full_name: row.full_name,
                                  },
                                )}
                            </div>
                          </>
                        ) : section === "payments" ? (
                          <>
                            <h2 className="font-bold">
                              {String(row.currency)} {String(row.amount)}
                            </h2>
                            <p>
                              {String(row.method)} /{" "}
                              {String(row.reference ?? "")}
                            </p>
                            <p>{String(row.received_at)}</p>
                            <p>
                              <UiText text="Reservation" />:{" "}
                              {String(row.reservation_id)}
                            </p>
                            {row.reverses_id ? (
                              <p>
                                <UiText text="Reversal" />: {String(row.reason)}
                              </p>
                            ) : row.reversed ? (
                              <p>
                                <UiText text="Reversed" />
                              </p>
                            ) : (
                              can("payments.reverse") && (
                                <>
                                  {actionButton(
                                    "Reverse payment",
                                    "reverse_payment",
                                    row,
                                  )}
                                  {can("payments.write") &&
                                    actionButton(
                                      "Correct payment",
                                      "correct_payment",
                                      row,
                                    )}
                                </>
                              )
                            )}
                          </>
                        ) : section === "staff" ? (
                          <>
                            <h2 className="font-bold">
                              {String(row.full_name)}
                            </h2>
                            <p>
                              <UiText text={label(row.role)} /> /{" "}
                              <UiText
                                text={row.active ? "Active" : "Inactive"}
                              />
                            </p>
                            <p className="break-words text-sm">
                              {Array.isArray(row.permissions)
                                ? row.permissions
                                    .map(
                                      (p) =>
                                        lodgePermissionLabels[String(p)] ??
                                        String(p),
                                    )
                                    .join(", ")
                                : ""}
                            </p>
                            {can("staff.manage") &&
                              row.role !== "owner" &&
                              row.active === true && (
                                <>
                                  {(row.role !== "manager" ||
                                    permissions.includes("*")) &&
                                    actionButton(
                                      "Change role and permissions",
                                      "set_staff",
                                      row,
                                    )}
                                  {operation("Remove access", "remove_staff", {
                                    profile_id: row.profile_id,
                                  })}
                                </>
                              )}
                          </>
                        ) : (
                          <>
                            <h2 className="font-bold">
                              {String(row.full_name)}
                            </h2>
                            <p>{String(row.phone ?? "")}</p>
                            <p>{String(row.email ?? "")}</p>
                            {can("guests.write") &&
                              actionButton("Edit guest", "save_guest", row)}
                          </>
                        )}
                      </article>
                    ))}
                  </div>
                )}
                {section === "reservations" &&
                  rows(data.enquiries).map((e) => (
                    <article
                      key={String(e.id)}
                      className="my-4 rounded-2xl bg-white p-5"
                    >
                      <h2 className="font-bold">
                        <UiText text="Reservation enquiry" />
                      </h2>
                      <p>
                        {String(e.arrival)} → {String(e.departure)} /{" "}
                        {String(e.guests)} <UiText text="guests" />
                      </p>
                      <p>{String(e.message)}</p>
                      <p>{String(e.contact_phone)}</p>
                      <div className="flex flex-wrap gap-2">
                        {can("reservations.write") && (
                          <>
                            {!e.reservation_id &&
                              operation(
                                "Confirm and allocate room",
                                "confirm_enquiry",
                                { id: e.id },
                              )}
                            {operation("Mark contacted", "enquiry_status", {
                              id: e.id,
                              status: "contacted",
                            })}
                            {operation("Close enquiry", "enquiry_status", {
                              id: e.id,
                              status: "closed",
                            })}
                          </>
                        )}
                      </div>
                    </article>
                  ))}
                {section === "staff" && (
                  <>
                    {rows(data.invitations).map((i) => (
                      <article
                        key={String(i.id)}
                        className="my-3 rounded-2xl bg-white p-5"
                      >
                        {String(i.email)} / <UiText text={label(i.role)} />
                        {can("staff.manage") &&
                          operation("Revoke invitation", "revoke_invitation", {
                            id: i.id,
                          })}
                      </article>
                    ))}
                    {rows(data.applications).map((a) => (
                      <article
                        key={String(a.id)}
                        className="my-3 rounded-2xl bg-white p-5"
                      >
                        <p>{String(a.notes)}</p>
                        {can("staff.manage") && (
                          <>
                            {operation(
                              "Approve management application",
                              "review_access",
                              { id: a.id, approved: true },
                            )}
                            {operation("Reject application", "review_access", {
                              id: a.id,
                              approved: false,
                            })}
                          </>
                        )}
                      </article>
                    ))}
                  </>
                )}
                {Number(data.total) === 0 && data.total !== undefined && (
                  <p className="my-4 rounded-2xl bg-white p-5">
                    <UiText text="No records for these filters." />
                  </p>
                )}
                {data.total !== undefined && (
                  <div className="mt-6 flex items-center justify-between">
                    <button
                      className="btn btn-outline"
                      disabled={offset === 0 || loading}
                      onClick={() => setOffset(Math.max(0, offset - 30))}
                    >
                      <UiText text="Previous" />
                    </button>
                    <span>
                      {offset + 1}–{Math.min(offset + 30, Number(data.total))} /{" "}
                      {String(data.total)}
                    </span>
                    <button
                      className="btn btn-outline"
                      disabled={offset + 30 >= Number(data.total) || loading}
                      onClick={() => setOffset(offset + 30)}
                    >
                      <UiText text="Next" />
                    </button>
                  </div>
                )}
              </>
            )}
          </>
        )
      )}
      {editor && (
        <div
          className="fixed inset-0 z-[100] overflow-y-auto bg-black/60 p-4"
          role="dialog"
          aria-modal="true"
          aria-labelledby="lodge-editor-title"
        >
          <form
            onSubmit={submit}
            className="mx-auto grid max-w-2xl gap-4 rounded-3xl bg-white p-5 text-[#17323a]"
          >
            <header className="flex justify-between gap-3">
              <h2 id="lodge-editor-title" className="text-2xl font-bold">
                <UiText
                  text={lodgeFormTitles[editor.action] ?? label(editor.action)}
                />
              </h2>
              <button
                type="button"
                disabled={busy}
                onClick={() => {
                  setEditor(null);
                  if (section === "register") navigate("/manage/lodges");
                }}
              >
                <UiText text="Close" />
              </button>
            </header>
            {["reserve", "block_room", "reservation_update"].includes(
              editor.action,
            ) && (
              <p>
                <UiText text="Dates use the lodge timezone" />:{" "}
                {String(lodge.timezone)}.{" "}
                <UiText text="Departure date is not included." />
              </p>
            )}
            {formError && (
              <p role="alert" className="rounded-xl bg-red-50 p-3 text-red-900">
                {formError}
              </p>
            )}
            {(lodgeForms[editor.action] ?? [])
              .filter(
                (f) =>
                  editor.action !== "reservation_update" ||
                  !editor.initial.accepted_at ||
                  ![
                    "arrival",
                    "departure",
                    "total_amount",
                    "status",
                    "guests",
                  ].includes(f.name),
              )
              .map((f) => (
                <label key={f.name} className="grid gap-2 font-semibold">
                  <UiText text={f.label} />
                  {f.type === "location" ? (
                    <EventLocationFields
                      value={location}
                      onChange={setLocation}
                      inputName="location_id"
                      required
                    />
                  ) : f.type === "checkbox" ? (
                    <input
                      name={f.name}
                      type="checkbox"
                      defaultChecked={editor.initial[f.name] === true}
                      className="h-6 w-6"
                    />
                  ) : f.type === "textarea" ? (
                    <textarea
                      className="rounded-xl border p-3 font-normal"
                      name={f.name}
                      required={f.required}
                      maxLength={10000}
                      defaultValue={String(editor.initial[f.name] ?? "")}
                    />
                  ) : f.type === "select" ||
                    [
                      "rooms",
                      "room",
                      "room_type",
                      "reservation",
                      "permissions",
                    ].includes(f.type ?? "") ? (
                    <select
                      name={f.name}
                      required={f.required}
                      multiple={["rooms", "permissions"].includes(f.type ?? "")}
                      className="rounded-xl border bg-white p-3 font-normal"
                      defaultValue={
                        f.type === "rooms"
                          ? ((editor.initial.room_ids as string[]) ?? [])
                          : f.type === "permissions"
                            ? ((editor.initial.permissions as string[]) ?? [])
                            : String(
                                editor.initial[f.name] ?? f.options?.[0] ?? "",
                              )
                      }
                    >
                      {f.options ? (
                        f.options.map((o) => (
                          <option key={o} value={o}>
                            {label(o)}
                          </option>
                        ))
                      ) : f.type === "permissions" ? (
                        lodgePermissions.map((p) => (
                          <option key={p} value={p}>
                            {lodgePermissionLabels[p] ?? p}
                          </option>
                        ))
                      ) : f.type === "reservation" ? (
                        <>
                          {editor.initial.reservation_id && (
                            <option
                              value={String(editor.initial.reservation_id)}
                            >
                              {String(editor.initial.code ?? "")} /{" "}
                              {String(
                                editor.initial.full_name ??
                                  editor.initial.reservation_id,
                              )}
                            </option>
                          )}
                          {bookings.map((b) => (
                            <option key={String(b.id)} value={String(b.id)}>
                              {String(b.code)} / {String(b.full_name)} /{" "}
                              {String(b.arrival)}
                            </option>
                          ))}
                        </>
                      ) : (
                        rooms.map((r) => (
                          <option key={String(r.id)} value={String(r.id)}>
                            {String(r.name ?? r.code)} /{" "}
                            {String(r.room_type ?? "")} / {String(r.currency)}{" "}
                            {String(r.nightly_rate)}
                          </option>
                        ))
                      )}
                    </select>
                  ) : (
                    <input
                      className="rounded-xl border bg-white p-3 font-normal"
                      name={f.name}
                      type={
                        [
                          "number",
                          "date",
                          "datetime-local",
                          "email",
                          "tel",
                        ].includes(f.type ?? "")
                          ? f.type
                          : "text"
                      }
                      required={f.required}
                      min={f.type === "number" ? 0 : undefined}
                      step={f.type === "number" ? "any" : undefined}
                      maxLength={f.name === "currency" ? 3 : 500}
                      defaultValue={
                        f.type === "array" &&
                        Array.isArray(editor.initial[f.name])
                          ? (editor.initial[f.name] as string[]).join(", ")
                          : String(editor.initial[f.name] ?? "")
                      }
                    />
                  )}
                </label>
              ))}
            {["save_room_type", "settings"].includes(editor.action) && (
              <div>
                <label className="grid gap-2 font-semibold">
                  <UiText text="Photos" />
                  <input
                    type="file"
                    accept="image/jpeg,image/png,image/webp"
                    multiple={editor.action !== "save_room_type"}
                    disabled={busy}
                    onChange={(e) => void upload(e.target.files)}
                  />
                </label>
                <p>
                  {photos.length}/{editor.action === "save_room_type" ? 1 : 20}
                </p>
                <LodgePhotos paths={photos} />
                {photos.map((path, i) => (
                  <button
                    key={path}
                    type="button"
                    className="m-1 rounded-xl border p-2"
                    onClick={() =>
                      setPhotos((old) => old.filter((_, n) => i !== n))
                    }
                  >
                    <UiText text="Remove photo" /> {i + 1}
                  </button>
                ))}
              </div>
            )}
            <button disabled={busy} className="btn btn-success">
              <UiText text={busy ? "Saving…" : "Save"} />
            </button>
          </form>
        </div>
      )}
    </main>
  );
}
