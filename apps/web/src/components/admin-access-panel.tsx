"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { getBrowserSupabase } from "@/lib/supabase-browser";

type Row = Record<string, unknown>;
type AssignedRole = { id: string; name: string };

export function AdminAccessPanel() {
  const supabase = useMemo(() => getBrowserSupabase(), []);
  const [users, setUsers] = useState<Row[]>([]);
  const [roles, setRoles] = useState<Row[]>([]);
  const [query, setQuery] = useState("");
  const [busyKey, setBusyKey] = useState("");
  const [message, setMessage] = useState("");

  const load = useCallback(async () => {
    const [directory, definitions] = await Promise.all([
      supabase.rpc("get_admin_role_directory"),
      supabase.from("admin_role_definitions").select("id,name,description,rank").eq("is_active", true).order("rank", { ascending: false }),
    ]);
    if (directory.error) setMessage(directory.error.message);
    else setUsers((directory.data as Row[] | null) ?? []);
    if (definitions.error) setMessage(definitions.error.message);
    else setRoles((definitions.data as Row[] | null) ?? []);
  }, [supabase]);

  useEffect(() => { queueMicrotask(() => void load()); }, [load]);

  async function assign(userId: string, roleId: string, enabled: boolean) {
    const roleName = String(roles.find((role) => role.id === roleId)?.name ?? roleId);
    if (!window.confirm(`${enabled ? "Assign" : "Remove"} ${roleName}? Administrative access changes immediately and will be audited.`)) return;
    const key = `${userId}:${roleId}`; setBusyKey(key); setMessage("");
    const result = await supabase.rpc("assign_admin_role", { p_user_id: userId, p_role_id: roleId, p_assign: enabled } as never);
    setMessage(result.error?.message ?? `${roleName} ${enabled ? "assigned" : "removed"}.`);
    setBusyKey(""); await load();
  }

  const filtered = users.filter((user) => `${user.full_name ?? ""} ${user.account_email ?? ""}`.toLowerCase().includes(query.toLowerCase()));
  return <section className="surface-card p-5 sm:p-7">
    <h2 className="font-heading text-3xl font-semibold">Admin access and roles</h2>
    <p className="mt-2 text-muted">Only a Super Admin can assign these roles. Every change is stored in the audit log.</p>
    <label className="field-label mt-5">Find a registered account<input className="field-input mt-2" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Name or account email" /></label>
    {message ? <p className="mt-4 rounded-xl bg-brand-info-soft p-4 text-sm" role="status">{message}</p> : null}
    <div className="mt-6 grid gap-5">{filtered.map((user) => {
      const assigned = (user.roles as AssignedRole[] | null) ?? [];
      const assignedIds = new Set(assigned.map((role) => role.id));
      return <article className="rounded-2xl border border-brand-border bg-brand-card-soft p-5" key={String(user.user_id)}>
        <div><h3 className="font-heading text-xl font-semibold">{String(user.full_name ?? "Unnamed account")}</h3><p className="text-sm text-muted">{String(user.account_email ?? "No email")}</p></div>
        <div className="mt-4 grid gap-3 md:grid-cols-2">{roles.map((role) => {
          const roleId = String(role.id); const enabled = assignedIds.has(roleId); const key = `${user.user_id}:${roleId}`;
          return <label className={`flex items-start justify-between gap-3 rounded-xl border p-4 ${enabled ? "border-brand-green bg-brand-green-soft" : "border-brand-border bg-white"}`} key={roleId}>
            <span><strong>{String(role.name)}</strong><span className="mt-1 block text-xs text-muted">{String(role.description)}</span></span>
            <input type="checkbox" checked={enabled} disabled={Boolean(busyKey)} onChange={(event) => void assign(String(user.user_id), roleId, event.target.checked)} aria-label={`${enabled ? "Remove" : "Assign"} ${String(role.name)}`} />
            {busyKey === key ? <span className="text-xs">Saving...</span> : null}
          </label>;
        })}</div>
      </article>;
    })}</div>
  </section>;
}
