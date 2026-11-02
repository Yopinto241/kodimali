"use client";
import { NavigationIndicator } from "@/components/navigation-progress";

import { useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import Link from 'next/link';
import { getBrowserSupabase } from '@/lib/supabase-browser';
import { UiText, UiInput } from '@/components/ui-text';
import { translateUiPrompt } from '@/lib/ui-translation';

type Location = { id: string; parent_id: string | null; name: string; location_type: string; is_active: boolean };
const childTypes: Record<string, string> = { country: 'region', region: 'district', district: 'ward', ward: 'area', area: 'street' };
const fields = 'id,parent_id,name,location_type,is_active';

export function ManageLocations() {
  const db = useMemo(() => getBrowserSupabase(), []);
  const [rows, setRows] = useState<Location[]>([]);
  const [ancestors, setAncestors] = useState<Location[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [revision, setRevision] = useState(0);
  const [editing, setEditing] = useState<Location | 'new' | null>(null);
  const [name, setName] = useState('');
  const editor = useRef<HTMLDialogElement>(null);
  useEffect(() => { if (!editing) return; const dialog = editor.current; dialog?.showModal(); return () => dialog?.close(); }, [editing]);
  const params = typeof window === 'undefined' ? new URLSearchParams() : new URLSearchParams(window.location.search);
  const parentId = params.get('parent');
  const page = Math.max(0, Number(params.get('page')) || 0);
  const search = params.get('q') ?? '';
  const href = (parent: string | null, nextPage = 0, query = '') => `/manage/locations?${new URLSearchParams({ ...(parent ? { parent } : {}), ...(nextPage ? { page: String(nextPage) } : {}), ...(query ? { q: query } : {}) })}`;

  useEffect(() => {
    let cancelled = false;
    async function load() {
      setLoading(true); setError('');
      try {
        const trail: Location[] = [];
        let current = parentId;
        if (!current) {
          const country = await db.from('locations').select('id').eq('location_type', 'country').ilike('name', 'Tanzania').single();
          if (country.error) throw country.error;
          current = String((country.data as { id: string }).id);
        }
        const scopeId = current;
        const visited = new Set<string>();
        while (current) {
          if (visited.has(current) || trail.length >= 8) throw new Error('Invalid location hierarchy.');
          visited.add(current);
          const result = await db.from('locations').select(fields).eq('id', current).single();
          if (result.error) throw result.error;
          const item = result.data as Location;
          trail.unshift(item); current = item.parent_id;
        }
        let query = db.from('locations').select(fields).order('name').order('id').range(page * 20, page * 20 + 19);
        query = query.eq('parent_id', scopeId);
        if (search.trim()) query = query.ilike('name', `%${search.trim().replace(/[%_]/g, '')}%`);
        const result = await query;
        if (result.error) throw result.error;
        if (!cancelled) { setRows(result.data as Location[]); setAncestors(trail); }
      } catch (cause) { if (!cancelled) setError(cause instanceof Error ? cause.message : String((cause as {message?: string}).message ?? cause)); }
      finally { if (!cancelled) setLoading(false); }
    }
    void load();
    return () => { cancelled = true; };
  }, [db, parentId, page, search, revision]);

  const parent = ancestors.at(-1);
  const childType = parent ? childTypes[parent.location_type] : '';
  const effectiveParentId = parent?.id ?? null;
  async function save(event: FormEvent) {
    event.preventDefault(); if (!editing || busy || !name.trim()) return;
    setBusy(true); setError('');
    try {
      const normalized = name.trim().replace(/\s+/g, ' ');
      let duplicate = db.from('locations').select('id').eq('location_type', editing === 'new' ? childType : editing.location_type).ilike('name', normalized.replace(/[%_]/g, '\\$&')).limit(1);
      duplicate = effectiveParentId ? duplicate.eq('parent_id', effectiveParentId) : duplicate.is('parent_id', null);
      if (editing !== 'new') duplicate = duplicate.neq('id', editing.id);
      const match = await duplicate;
      if (match.error) throw match.error;
      if (match.data?.length) throw new Error('A location with this name already exists under this parent.');
      const result = editing === 'new'
        ? await db.from('locations').insert({ name: normalized, location_type: childType, parent_id: effectiveParentId } as never)
        : await db.from('locations').update({ name: normalized } as never).eq('id', editing.id);
      if (result.error) throw result.error;
      setEditing(null); setRevision(value => value + 1);
    } catch (cause) { setError(String((cause as {message?: string}).message ?? cause)); }
    finally { setBusy(false); }
  }
  async function remove(row: Location) {
    if (!window.confirm(translateUiPrompt('Delete this location? Referenced locations cannot be deleted.'))) return;
    setBusy(true); setError('');
    try {
      const result = await db.rpc('manage_delete_unused_location', { p_location_id: row.id } as never);
      if (result.error) throw result.error;
      setRevision(value => value + 1);
    } catch (cause) { setError(String((cause as {message?: string}).message ?? cause)); }
    finally { setBusy(false); }
  }
  return <div className="grid gap-4">
    <nav aria-label="Location hierarchy" className="flex flex-wrap gap-2 text-sm"><Link prefetch={false} href={href(null)}><UiText text="Locations" /></Link>{ancestors.map(row => <span key={row.id}> / <Link prefetch={false} href={href(row.id)}>{row.name}</Link></span>)}</nav>
    <div className="surface-card grid gap-4 p-5">
      <div className="flex flex-wrap items-center justify-between gap-3"><h2 className="text-xl font-bold">{parent?.name ?? <UiText text="Locations" />}</h2>{childType && <button className="btn btn-success" disabled={busy || loading} onClick={() => {setName(''); setEditing('new');}}><UiText text="Add" /> <UiText text={childType} /></button>}</div>
      <form action="/manage/locations" className="flex gap-2"><input type="hidden" name="parent" value={parentId ?? ''} /><UiInput className="min-w-0 flex-1 rounded-xl border border-brand-border p-3" name="q" defaultValue={search} placeholder="Search" aria-label="Search" /><button className="btn btn-outline"><UiText text="Search" /></button></form>
      {error && <div role="alert" className="rounded-xl bg-red-50 p-4 text-red-800"><UiText text={error} /> <button className="underline" onClick={() => setRevision(value => value + 1)}><UiText text="Retry" /></button></div>}
      {loading ? <NavigationIndicator inline /> : rows.length === 0 ? <p><UiText text="No locations found." /></p> : rows.map(row => <article key={row.id} className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-brand-border p-4"><div>{childTypes[row.location_type] ? <Link prefetch={false} className="font-bold underline decoration-brand-green" href={href(row.id)}>{row.name} →</Link> : <h3 className="font-bold">{row.name}</h3>}<p className="text-sm text-muted"><UiText text={row.location_type} /> · <UiText text={row.is_active ? 'Active' : 'Inactive'} /></p></div><div className="flex gap-2"><button className="btn btn-outline" disabled={busy} onClick={() => {setName(row.name); setEditing(row);}}><UiText text="Edit" /></button><button className="btn btn-outline" disabled={busy} onClick={() => void remove(row)}><UiText text="Delete" /></button></div></article>)}
      <div className="flex justify-between">{page > 0 ? <Link prefetch={false} className="btn btn-outline" href={href(parentId, page - 1, search)}><UiText text="Previous" /></Link> : <span />}{rows.length === 20 && <Link prefetch={false} className="btn btn-outline" href={href(parentId, page + 1, search)}><UiText text="Next" /></Link>}</div>
    </div>
    {editing && <dialog ref={editor} aria-labelledby="location-editor-title" className="surface-card manage-dialog p-5" onCancel={event => {if (busy) event.preventDefault(); else setEditing(null);}}><form onSubmit={save} className="grid gap-4"><h2 id="location-editor-title" className="font-bold"><UiText text={editing === 'new' ? 'Add' : 'Edit'} /> <UiText text={editing === 'new' ? childType : editing.location_type} /></h2><p><UiText text="Parent" />: {parent?.name ?? <UiText text="No parent" />}</p><label className="grid gap-2"><UiText text="Location name" /><input autoFocus required maxLength={160} className="rounded-xl border border-brand-border p-3" value={name} onChange={event => setName(event.target.value)} /></label><div className="flex gap-3"><button disabled={busy} className="btn btn-success"><UiText text="Save" /></button><button type="button" disabled={busy} className="btn btn-outline" onClick={() => setEditing(null)}><UiText text="Cancel" /></button></div></form></dialog>}
  </div>;
}
