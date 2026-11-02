"use client";
import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { getBrowserSupabase } from '@/lib/supabase-browser';
import { UiInput, UiSelect, UiText } from '@/components/ui-text';

export function ManageListingFilters({ role, hasMore, detail }: { role: 'admin' | 'agent'; hasMore: boolean; detail?: boolean }) {
  const db = useMemo(() => getBrowserSupabase(), []);
  const [categories, setCategories] = useState<{id: string; name: string}[]>([]);
  const params = typeof window === 'undefined' ? new URLSearchParams() : new URLSearchParams(window.location.search);
  const page = Math.max(0, Number(params.get('page')) || 0);
  useEffect(() => { let live = true; void db.from('asset_categories').select('id,name').order('name').limit(100).then(result => { if (live && !result.error) setCategories(result.data); }); return () => {live = false;}; }, [db]);
  const pageHref = (next: number) => { const query = new URLSearchParams(params); query.set('page', String(next)); query.set('workspace', role); return `/manage/listings?${query}`; };
  if (detail) return <Link prefetch={false} className="btn btn-outline mb-4" href={`/manage/listings?${params}`}><UiText text="Back to listings" /></Link>;
  return <div className="surface-card mb-4 grid gap-4 p-4"><form action="/manage/listings" className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
    <input name="workspace" value={role} type="hidden" />
    <UiInput name="q" defaultValue={params.get('q') ?? ''} placeholder="Search listings" aria-label="Search listings" className="rounded-xl border border-brand-border p-3" />
    <UiSelect name="status" defaultValue={params.get('status') ?? ''} aria-label="Status" className="rounded-xl border border-brand-border p-3"><option value=""><UiText text="All statuses" /></option>{['draft','active','inactive','expired','suspended'].map(status => <option key={status} value={status}><UiText text={status} /></option>)}</UiSelect>
    <UiSelect name="category" defaultValue={params.get('category') ?? ''} aria-label="Category" className="rounded-xl border border-brand-border p-3"><option value=""><UiText text="All categories" /></option>{categories.map(category => <option key={category.id} value={category.id}>{category.name}</option>)}</UiSelect>
    {role === 'admin' && <UiSelect name="review" defaultValue={params.get('review') ?? ''} aria-label="Review" className="rounded-xl border border-brand-border p-3"><option value=""><UiText text="All reviews" /></option>{['pending','auto_approved','admin_approved','rejected'].map(value => <option key={value} value={value}><UiText text={value} /></option>)}</UiSelect>}
    <button className="btn btn-success"><UiText text="Search" /></button>
  </form><div className="flex justify-between">{page > 0 ? <Link prefetch={false} className="btn btn-outline" href={pageHref(page - 1)}><UiText text="Previous" /></Link> : <span />}{hasMore && <Link prefetch={false} className="btn btn-outline" href={pageHref(page + 1)}><UiText text="Next" /></Link>}</div></div>;
}
