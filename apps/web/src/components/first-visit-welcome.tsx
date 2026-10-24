"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";

const deviceKey = "kodimali_browser_device_id";
const welcomeKey = "kodimali_welcome_seen_v1";

export function FirstVisitWelcome() {
  const [open, setOpen] = useState(false);
  const [reading, setReading] = useState(false);
  const dialogRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    try {
      let deviceId = window.localStorage.getItem(deviceKey);
      if (!deviceId) {
        deviceId = typeof crypto.randomUUID === "function"
          ? crypto.randomUUID()
          : `browser-${Date.now()}-${Math.random().toString(36).slice(2)}`;
        window.localStorage.setItem(deviceKey, deviceId);
      }
      if (window.localStorage.getItem(welcomeKey) !== deviceId) {
        queueMicrotask(() => setOpen(true));
      }
    } catch {
      // Browsers that block local storage get one welcome per page lifecycle.
      queueMicrotask(() => setOpen(true));
    }
  }, []);

  useEffect(() => {
    if (!open) return;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    dialogRef.current?.focus();
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") dismiss();
    };
    window.addEventListener("keydown", closeOnEscape);
    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener("keydown", closeOnEscape);
    };
  }, [open]);

  function dismiss() {
    try {
      const deviceId = window.localStorage.getItem(deviceKey);
      if (deviceId) window.localStorage.setItem(welcomeKey, deviceId);
    } catch {
      // Closing the dialog must still work when storage is unavailable.
    }
    setOpen(false);
  }

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-[100] flex items-end justify-center bg-[#071426]/70 p-3 backdrop-blur-md sm:items-center sm:p-6" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) dismiss(); }}>
      <div ref={dialogRef} role="dialog" aria-modal="true" aria-labelledby="welcome-title" tabIndex={-1} className="relative w-full max-w-2xl overflow-hidden rounded-[32px] border border-white/20 bg-white shadow-[0_32px_100px_rgba(3,12,28,0.45)] outline-none">
        <div className="relative overflow-hidden bg-brand-navy px-6 pb-7 pt-8 text-white sm:px-9 sm:pt-10">
          <div className="absolute -right-16 -top-20 h-52 w-52 rounded-full bg-brand-green/25 blur-2xl" />
          <div className="absolute -bottom-24 -left-12 h-48 w-48 rounded-full bg-[#3f83c5]/25 blur-2xl" />
          <button type="button" onClick={dismiss} className="absolute right-5 top-5 rounded-full border border-white/20 bg-white/10 px-3 py-2 text-sm font-bold text-white transition hover:bg-white/20" aria-label="Funga">Ruka</button>
          <p className="relative text-xs font-black uppercase tracking-[0.25em] text-brand-green">Karibu KODIMALI</p>
          <h2 id="welcome-title" className="relative mt-4 max-w-xl font-heading text-3xl font-semibold leading-tight sm:text-4xl">Mali na shughuli zako, sehemu moja.</h2>
          <p className="relative mt-4 max-w-xl text-base leading-7 text-white/80">Tafuta mali, toa taarifa ya mali inayopatikana, na ufuatilie miadi au booking kwa akaunti yako.</p>
        </div>

        <div className="p-6 sm:p-9">
          {reading ? (
            <div className="grid gap-3 sm:grid-cols-3">
              <WelcomePoint number="01" title="Tafuta" body="Linganisha mali, bei na maeneo kabla ya kutuma ombi." />
              <WelcomePoint number="02" title="Toa taarifa" body="Taarifa unayotuma hukaguliwa kwanza na mawasiliano ya mmiliki hayachapishwi." />
              <WelcomePoint number="03" title="Fuatilia" body="Akaunti yako huhifadhi taarifa, miadi, booking na ustahiki wa zawadi." />
            </div>
          ) : (
            <p className="text-sm leading-6 text-muted">KODIMALI haichapishi taarifa ya referral moja kwa moja. Tunathibitisha mali na ruhusa ya mmiliki kwanza. Zawadi hutegemea lead kustahili na deal kukamilika.</p>
          )}

          <div className="mt-6 flex flex-col-reverse gap-3 sm:flex-row sm:items-center sm:justify-between">
            <button type="button" className="btn btn-ghost" onClick={() => setReading((value) => !value)}>{reading ? "Fupisha" : "Soma zaidi"}</button>
            <div className="flex gap-3">
              <button type="button" className="btn btn-outline flex-1 sm:flex-none" onClick={dismiss}>Ruka</button>
              <Link href="/listings" className="btn btn-success flex-1 sm:flex-none" onClick={dismiss}>Anza sasa</Link>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function WelcomePoint({ number, title, body }: { number: string; title: string; body: string }) {
  return <article className="rounded-2xl border border-brand-border bg-brand-card-soft p-4"><p className="text-xs font-black tracking-[0.2em] text-brand-green-strong">{number}</p><h3 className="mt-2 font-heading text-xl font-semibold">{title}</h3><p className="mt-2 text-sm leading-6 text-muted">{body}</p></article>;
}
