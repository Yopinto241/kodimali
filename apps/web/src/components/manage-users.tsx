"use client";
import { NavigationIndicator } from "@/components/navigation-progress";
import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { getBrowserSupabase } from '@/lib/supabase-browser';
import { UiInput, UiSelect, UiText } from '@/components/ui-text';

type Customer = { id: string; full_name: string | null; account_email: string | null; phone_number: string | null; preferred_language: string; email_confirmed_at: string | null; created_at: string; updated_at: string };
export function ManageUsers({ recordId }: { recordId?: string }) {
  const db = useMemo(() => getBrowserSupabase(), []);
  const [rows, setRows] = useState<Customer[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [revision, setRevision] = useState(0);
  const params = typeof window === 'undefined' ? new URLSearchParams() : new URLSearchParams(window.location.search);
  const page = Math.max(0, Number(params.get('page')) || 0);
  const search = params.get('q') ?? '';
  const confirmation = params.get('confirmation') ?? '';
  const query = params.toString();
  const pageHref = (next: number) => { const copy = new URLSearchParams(query); copy.set('page', String(next)); return `/manage/users?${copy}`; };
  useEffect(() => {
    let cancelled = false;
    async function load() {
      setLoading(true); setError('');
      const result = await db.rpc('search_manage_customers', { p_search: search || null, p_confirmation: confirmation || null, p_offset: recordId ? 0 : page * 20, p_limit: recordId ? 1 : 20, p_id: recordId ?? null } as never);
      if (cancelled) return;
      if (result.error) setError(result.error.code === 'PGRST202' ? 'Customer directory update is required before this feature can load.' : result.error.message);
      else setRows((result.data ?? []) as Customer[]);
      setLoading(false);
    }
    void load().catch(cause => { if (!cancelled) {setError(String(cause)); setLoading(false);} });
    return () => {cancelled = true;};
  }, [db, page, search, confirmation, recordId, revision]);
  return <div className="surface-card grid gap-4 p-5">
    {recordId ? <Link prefetch={false} className="font-semibold underline" href={`/manage/users?${query}`}><UiText text="Back to users" /></Link> : <form action="/manage/users" className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_180px_auto]">
      <UiInput name="q" defaultValue={search} placeholder="Name, email or phone" aria-label="Search users" className="rounded-xl border border-brand-border p-3" />
      <UiSelect name="confirmation" defaultValue={confirmation} aria-label="Email confirmation" className="rounded-xl border border-brand-border p-3"><option value=""><UiText text="All statuses" /></option><option value="confirmed"><UiText text="Email confirmed" /></option><option value="pending"><UiText text="Confirmation pending" /></option></UiSelect>
      <button className="btn btn-success"><UiText text="Search" /></button>
    </form>}
    {loading ? <NavigationIndicator inline /> : error ? <div role="alert" className="rounded-xl bg-red-50 p-4 text-red-800"><UiText text={error} /> <button className="underline" onClick={() => setRevision(value => value + 1)}><UiText text="Retry" /></button></div> : rows.length === 0 ? <p><UiText text="No users found." /></p> : <div className={recordId ? 'grid gap-4' : 'manage-users-grid'}>{rows.map(user => <article key={user.id} className="manage-user-row">
      <div><h2 className="font-bold">{recordId ? user.full_name || <UiText text="KODIMALI user" /> : <Link prefetch={false} href={`/manage/users/${user.id}?${query}`} className="underline">{user.full_name || <UiText text="KODIMALI user" />}</Link>}</h2><p>{user.account_email || <UiText text="No email" />}</p></div>
      <p>{user.phone_number || <UiText text="No phone number" />}</p>
      <p><UiText text={user.email_confirmed_at ? 'Email confirmed' : 'Confirmation pending'} /></p>
      <p className="text-sm"><UiText text="Registered" />: {new Date(user.created_at).toLocaleDateString()}</p>
      {recordId && <dl className="grid gap-2"><dt><UiText text="Preferred language" /></dt><dd>{user.preferred_language}</dd><dt><UiText text="Updated" /></dt><dd>{new Date(user.updated_at).toLocaleString()}</dd></dl>}
    </article>)}</div>}
    {!recordId && !loading && !error && <div className="flex justify-between">{page > 0 ? <Link prefetch={false} className="btn btn-outline" href={pageHref(page - 1)}><UiText text="Previous" /></Link> : <span />}{rows.length === 20 && <Link prefetch={false} className="btn btn-outline" href={pageHref(page + 1)}><UiText text="Next" /></Link>}</div>}
  </div>;
}
