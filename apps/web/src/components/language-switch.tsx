"use client";

import { AppLanguage, useLanguage } from "@/components/language-provider";

export function LanguageSwitch() {
  const { language, setLanguage, t } = useLanguage();
  return <label className="flex shrink-0 items-center text-xs font-bold text-brand-navy"><span className="sr-only">{t("language.label")}</span><select aria-label={t("language.label")} className="nav-control max-w-[118px] px-3 text-brand-navy" value={language} onChange={(event) => setLanguage(event.target.value as AppLanguage)}><option value="sw">{t("language.sw")}</option><option value="en">{t("language.en")}</option></select></label>;
}
