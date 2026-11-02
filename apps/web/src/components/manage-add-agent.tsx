"use client";

import { useEffect, useState } from "react";
import { AgentRegistrationForm } from "@/components/agent-registration-form";
import { UiText } from "@/components/ui-text";
import { getBrowserSupabase } from "@/lib/supabase-browser";

type Option = { id: string; name: string };

export function ManageAddAgent({ onCreated, scoped = false }: { onCreated: () => void; scoped?: boolean }) {
  const [scope, setScope] = useState<{active: boolean; location_id: string; location_name: string; location_type: string} | null>(null);
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [options, setOptions] = useState<{ categories: Option[]; regions: Option[] } | null>(null);
  useEffect(() => { if (scoped) void getBrowserSupabase().rpc("get_my_supervisor_context").then(({ data }) => setScope(data)); }, [scoped]);

  async function show() {
    setOpen(true);
    if (options) return;
    setLoading(true); setError("");
    try {
      const client = getBrowserSupabase();
      const [categories, regions] = await Promise.all([
        client.from("asset_categories").select("id,name").eq("is_active", true).order("name"),
        client.from("locations").select("id,name").eq("location_type", "region").eq("is_active", true).order("name"),
      ]);
      if (categories.error || regions.error) throw new Error("Could not load agent registration options.");
      setOptions({ categories: categories.data ?? [], regions: regions.data ?? [] });
    } catch { setError("Could not load agent registration options."); }
    finally { setLoading(false); }
  }

  return <section className="mb-5">
    {scoped && <p className="soft-panel mb-3 p-3"><UiText text={scope?.active ? "Your assigned territory" : "Ask Super Admin to activate your supervisor territory before adding agents."} />{scope?.active && <>: {scope.location_name}</>}</p>}
    <button type="button" disabled={scoped && !scope?.active} className="btn btn-success" aria-expanded={open} aria-controls="add-agent-form" onClick={() => open ? setOpen(false) : void show()}>
      <UiText text={open ? "Close" : "Add agent"} />
    </button>
    {open && <div id="add-agent-form">
      {loading && <p role="status"><UiText text="Loading..." /></p>}
      {error && <div role="alert"><p><UiText text={error} /></p><button type="button" className="btn btn-outline" onClick={() => void show()}><UiText text="Retry" /></button></div>}
      {options && <AgentRegistrationForm {...options} staffCreation onCreated={onCreated} assignedLocation={scoped && scope?.active ? {id: scope.location_id, name: scope.location_name, location_type: scope.location_type} : undefined} />}
    </div>}
  </section>;
}
