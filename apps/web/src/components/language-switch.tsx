"use client";

import { AppLanguage, useLanguage } from "@/components/language-provider";

export function LanguageSwitch() {
  const { language, setLanguage, t } = useLanguage();
  return <label className="flex shrink-0 items-center text-xs font-bold text-brand-navy"><span className="sr-only">{t("language.label")}</span><select aria-label={t("language.label")} className="max-w-[118px] rounded-full border border-brand-border bg-brand-card-soft px-3 py-2 text-brand-navy" value={language} onChange={(event) => setLanguage(event.target.value as AppLanguage)}><option value="sw">{t("language.sw")}</option><option value="en">{t("language.en")}</option></select></label>;
}
