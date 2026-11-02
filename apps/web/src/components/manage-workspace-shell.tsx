"use client";

import { useEffect, useRef, useState, type ReactNode } from 'react';
import Image from "next/image";
import Link from 'next/link';
import { UiText, UiNav } from '@/components/ui-text';
import { manageHref, type ManageSection } from '@/lib/manage-routes';
import { LanguageSwitch } from '@/components/language-switch';

export function ManageWorkspaceShell({ section, role, tabs, signOut, children, availableRoles }: {
  section: ManageSection;
  role: 'admin' | 'agent';
  tabs: { id: ManageSection; label: string }[];
  signOut: () => void;
  children: ReactNode;
  availableRoles: string[];
}) {
  const [open, setOpen] = useState(false);
  const menuButton = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    if (!open) return;
    const listener = (event: KeyboardEvent) => { if (event.key === 'Escape') {setOpen(false); menuButton.current?.focus();} };
    window.addEventListener('keydown', listener);
    return () => window.removeEventListener('keydown', listener);
  }, [open]);
  const title = tabs.find(item => item.id === section)?.label ?? 'Access unavailable';
  return <main className="manage-workspace">
    <header className="manage-header">
      <Link prefetch={false} href={manageHref('dashboard', role)} className="manage-brand"><Image src="/icon.png" alt="KODIMALI" width={36} height={36} /><span>KODIMALI <small>Manage</small></span></Link>
      <LanguageSwitch />
      <button ref={menuButton} className="manage-menu-button" aria-expanded={open} aria-controls="manage-navigation" onClick={() => setOpen(!open)}><UiText text={open ? 'Close' : 'Menu'} /></button>
    </header>
    <div className="manage-layout">
      {open ? <button className="manage-scrim" aria-label="Close" onClick={() => setOpen(false)} /> : null}
      <UiNav id="manage-navigation" className={`manage-sidebar ${open ? 'is-open' : ''}`} aria-label="Management navigation">
        {tabs.map(item => <Link prefetch={false} key={item.id} href={manageHref(item.id, role)} aria-current={section === item.id ? 'page' : undefined} onClick={() => setOpen(false)}><UiText text={item.label} /></Link>)}
        <Link prefetch={false} href="/account"><UiText text="Customer account" /></Link>
        {availableRoles.includes('admin') && role !== 'admin' && <Link prefetch={false} href="/admin"><UiText text="Admin workspace" /></Link>}
        {availableRoles.includes('agent') && role !== 'agent' && <Link prefetch={false} href="/agent"><UiText text="Agent workspace" /></Link>}
        {availableRoles.includes('agent') && role !== 'agent' && <Link prefetch={false} href={manageHref('add-listing', 'agent')}><UiText text="Add my asset" /></Link>}
        {availableRoles.includes('owner') && <Link prefetch={false} href="/owner"><UiText text="Owner workspace" /></Link>}
        <button className="btn btn-outline m-3" onClick={signOut}><UiText text="Sign out" /></button>
      </UiNav>
      <section className="manage-content"><div className="manage-page-heading"><p><UiText text={role === 'admin' ? 'Admin workspace' : 'Agent workspace'} /></p><h1><UiText text={title} /></h1></div>{children}</section>
    </div>
  </main>;
}
