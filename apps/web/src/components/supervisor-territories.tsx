"use client";
import { safeUserMessage } from "@/lib/user-message";

import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from "react";
import { getBrowserSupabase } from "@/lib/supabase-browser";
import { UiText } from "@/components/ui-text";
import { translateUiPrompt } from "@/lib/ui-translation";

type Supervisor = { supervisor_id: string; full_name: string; account_email: string; location_id: string | null; location_name: string | null; is_active: boolean; agent_count: number };
const Directory = createContext<{ rows: Supervisor[]; refresh: () => Promise<void>; error: string }>({ rows: [], refresh: async () => {}, error: "" });

export function SupervisorTeams({ enabled, children }: { enabled: boolean; children: ReactNode }) {
  const [rows, setRows] = useState<Supervisor[]>([]);
  const [error, setError] = useState("");
  const refresh = useCallback(async () => {
    const result = await getBrowserSupabase().rpc("get_supervisor_directory");
    if (result.error) setError(safeUserMessage(result.error));
    else { setRows((result.data ?? []) as Supervisor[]); setError(""); }
  }, []);
  useEffect(() => { if (enabled) queueMicrotask(() => void refresh()); }, [enabled, refresh]);
  return <Directory.Provider value={{ rows, refresh, error }}>{children}</Directory.Provider>;
}

type Location = { id: string; name: string; location_type: string };
export function SupervisorLocationChoice({ onChange, root, requireArea = false, onAreaDraftChange }: { onChange: (id: string) => void; root?: Location; requireArea?: boolean; onAreaDraftChange?: (draft: { wardId: string; name: string } | null) => void }) {
  const [path, setPath] = useState<Location[]>([]);
  const [options, setOptions] = useState<Location[]>([]);
  const [areaName, setAreaName] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const request = useRef(0);
  const pending = useRef<AbortController | null>(null);
  const load = useCallback(async (parent?: Location) => {
    const id = ++request.current;
    pending.current?.abort();
    const controller = new AbortController();
    pending.current = controller;
    const timer = setTimeout(() => controller.abort(), 10000);
    setLoading(true); setOptions([]); setError("");
    try {
      const query = getBrowserSupabase().from("locations").select("id,name,location_type").eq("is_active", true).order("name").limit(500).abortSignal(controller.signal);
      const result = parent ? await query.eq("parent_id", parent.id) : await query.eq("location_type", "country");
      if (id !== request.current) return;
      if (result.error) throw result.error;
      setOptions(result.data ?? []);
    } catch {
      if (id === request.current) setError("Sorry, locations could not load. Please try again shortly.");
    } finally {
      clearTimeout(timer);
      if (id === request.current) setLoading(false);
    }
  }, []);
  useEffect(() => {
    queueMicrotask(() => { if (root) { setPath([root]); void load(root); } else void load(); });
    // Invalidate the latest asynchronous request; this ref is a counter, not a DOM node.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    return () => { request.current++; pending.current?.abort(); };
  }, [load, root]);
  function clearDraft() { setAreaName(""); onAreaDraftChange?.(null); }
  function choose(item: Location, next: Location[]) { clearDraft(); setPath(next); onChange((requireArea ? item.location_type !== "area" : item.location_type === "country") ? "" : item.id); void load(item); }
  const ward = path.at(-1)?.location_type === "ward" ? path.at(-1) : undefined;
  return <div className="grid gap-2">
    <span className="field-label"><UiText text={requireArea ? "Agent operating area" : "Supervisor territory"} /></span>
    {requireArea && <p><UiText text={root ? "Choose an area inside the assigned territory for this agent." : "Choose your region, district, ward and operating area."} /></p>}
    <div className="flex flex-wrap gap-2">{!root && <button className="btn btn-outline" type="button" onClick={() => { clearDraft(); setPath([]); onChange(""); void load(); }}><UiText text="Reset" /></button>}{path.map((item, index) => <button type="button" className="btn btn-outline" key={item.id} onClick={() => choose(item, path.slice(0, index + 1))}>{item.name}</button>)}</div>
    {loading ? <p role="status"><UiText text="Loading..." /></p> : options.length > 0 && <select className="field-input" aria-label={translateUiPrompt("Choose location")} value="" onChange={(event) => { const item = options.find((row) => row.id === event.target.value); if (item) choose(item, [...path, item]); }}><option value=""><UiText text="Choose location" /></option>{options.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select>}
    {requireArea && onAreaDraftChange && ward && <label className="field-label"><UiText text="New area name" />
      <input className="field-input mt-2" maxLength={100} value={areaName} onChange={(event) => { setAreaName(event.target.value); onChange(""); onAreaDraftChange({ wardId: ward.id, name: event.target.value }); }} />
      <span className="mt-2 block text-sm"><UiText text="If this area does not exist yet, type it here and it will be saved under the selected ward." /></span>
    </label>}
    {error && <div role="alert"><UiText text={error} /><button type="button" className="btn btn-outline mt-2" onClick={() => void load(path.at(-1))}><UiText text="Retry" /></button></div>}
  </div>;
}

export function SupervisorTerritories() {
  const directory = useContext(Directory);
  const [expanded, setExpanded] = useState(false);
  const [email, setEmail] = useState("");
  const [location, setLocation] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  async function save(address: string, locationId: string, active: boolean) {
    setBusy(true); setNotice("");
    const result = await getBrowserSupabase().rpc("configure_supervisor_territory", { p_email: address, p_location_id: locationId, p_active: active } as never);
    setNotice((result.error?.message ? safeUserMessage(result.error?.message) : null) ?? "Supervisor territory saved.");
    setBusy(false); await directory.refresh();
  }
  return <section className="soft-panel mb-5 p-4"><button type="button" className="cursor-pointer text-left font-semibold" aria-expanded={expanded} aria-controls="supervisor-territory-panel" onClick={() => setExpanded(!expanded)}><UiText text="Supervisors and territories" /></button>
    {expanded && <div id="supervisor-territory-panel">
    <p className="my-3"><UiText text="Only Super Admin assigns locations and transfers agents. Each agent belongs to one supervisor." /></p>
    <p className="my-3"><UiText text="Register as an agent first. Super Admin then appoints you as a supervisor and assigns your territory. Sign in again and open Manage > Agents to supervise your team." /></p>
    <form className="grid gap-3" onSubmit={(event) => { event.preventDefault(); void save(email, location, true); }}>
      <label className="field-label"><UiText text="Registered agent email" /><input type="email" required className="field-input" value={email} onChange={(event) => setEmail(event.target.value)} /></label>
      <SupervisorLocationChoice onChange={setLocation} />
      <button className="btn btn-success" disabled={busy || !location}><UiText text="Assign supervisor territory" /></button>
    </form>
    {(notice || directory.error) && <p className="mt-3" role="status"><UiText text={notice || directory.error} /></p>}
    <div className="mt-4 grid gap-3">{directory.rows.map((row) => <article className="rounded-xl border p-3" key={row.supervisor_id}>
      <strong>{row.full_name || row.account_email}</strong><p>{row.location_name ?? "—"} · {row.agent_count} <UiText text="Agents" /></p>
      <p><UiText text={row.is_active ? "Active" : "Inactive"} /></p>
      {row.location_id && <button type="button" className="btn btn-outline" disabled={busy} onClick={() => void save(row.account_email, row.location_id!, !row.is_active)}><UiText text={row.is_active ? "Deactivate" : "Activate"} /></button>}
    </article>)}</div>
  </div>}</section>;
}

export function AgentTeamAssignment({ agentId, supervisorId, onSaved }: { agentId: string; supervisorId: string; onSaved: () => void }) {
  const { rows, refresh } = useContext(Directory);
  const [selected, setSelected] = useState(supervisorId);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  useEffect(() => { queueMicrotask(() => setSelected(supervisorId)); }, [supervisorId]);
  async function save() {
    if (!window.confirm(translateUiPrompt("Transfer this agent? The previous supervisor will lose access immediately."))) return;
    setBusy(true); setNotice("");
    const result = await getBrowserSupabase().rpc("assign_agent_supervisor", { p_agent_id: agentId, p_supervisor_id: selected || null } as never);
    setBusy(false); setNotice((result.error?.message ? safeUserMessage(result.error?.message) : null) ?? "Agent team saved.");
    if (!result.error) { onSaved(); await refresh(); }
  }
  return <div className="mt-3 grid gap-2"><label className="field-label"><UiText text="Assigned supervisor" /><select className="field-input" value={selected} onChange={(event) => setSelected(event.target.value)} disabled={busy}>
    <option value=""><UiText text="Unassigned" /></option>{rows.filter((row) => row.is_active || row.supervisor_id === supervisorId).map((row) => <option key={row.supervisor_id} value={row.supervisor_id}>{row.full_name || row.account_email} · {row.location_name ?? "—"}</option>)}
  </select></label><button type="button" className="btn btn-outline" disabled={busy || selected === supervisorId} onClick={() => void save()}><UiText text="Save agent team" /></button>{notice && <p role="status"><UiText text={notice} /></p>}</div>;
}
