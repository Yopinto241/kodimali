"use client";

import { useEffect, useState } from "react";

export function LanguageSwitch() {
  const [language, setLanguage] = useState("sw");
  useEffect(() => { queueMicrotask(() => { const value = localStorage.getItem("kodimali-language") || "sw"; setLanguage(value); document.documentElement.lang = value; }); }, []);
  function change(value: string) { setLanguage(value); localStorage.setItem("kodimali-language", value); document.documentElement.lang = value; document.cookie = `kodimali_language=${value};path=/;max-age=31536000;samesite=lax`; }
  return <label className="flex shrink-0 items-center text-xs font-bold text-brand-navy"><span className="sr-only">Language</span><select aria-label="Website language" className="max-w-[112px] rounded-full border border-brand-border bg-brand-card-soft px-3 py-2 text-brand-navy" value={language} onChange={(e) => change(e.target.value)}><option value="sw">Kiswahili</option><option value="en">English</option></select></label>;
}
