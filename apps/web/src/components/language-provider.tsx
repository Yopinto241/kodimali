"use client";

import { createContext, ReactNode, useContext, useEffect, useMemo, useState } from "react";

export type AppLanguage = "sw" | "en";

const messages = {
  sw: {
    "language.label": "Lugha",
    "language.sw": "Kiswahili",
    "language.en": "English",
    "nav.home": "Nyumbani",
    "nav.listings": "Mali",
    "nav.events": "Sherehe na Matukio",
    "nav.referral": "Toa Taarifa",
    "nav.compare": "Linganisha",
    "nav.categories": "Aina za mali",
    "nav.account": "Akaunti",
    "nav.search": "Tafuta mali",
    "auth.loading": "Inapakia akaunti",
    "auth.login": "Ingia",
    "auth.register": "Jisajili",
    "auth.account": "Akaunti Yangu",
    "auth.logout": "Toka",
    "footer.tagline": "Tafuta mali kwa urahisi na uwasiliane na wakala aliyethibitishwa.",
    "footer.body": "Angalia mali, linganisha maeneo na bei, kisha fungua mawasiliano ya wakala unapokuwa tayari.",
    "footer.browse": "Angalia mali",
    "footer.payment": "Jinsi malipo yanavyofanya kazi",
    "footer.manage": "Usimamizi: Wakala, Mmiliki na Admin",
    "footer.links": "Viungo muhimu",
    "footer.support": "Msaada",
    "footer.home": "Nyumbani", "footer.all": "Mali zote", "footer.apartments": "Apartment", "footer.houses": "Nyumba", "footer.cars": "Magari", "footer.compare": "Linganisha mali", "footer.map": "Ramani ya mali za karibu", "footer.advertise": "Tangaza na KODIMALI", "footer.download": "Pakua programu", "footer.safety": "Usalama", "footer.privacy": "Faragha", "footer.terms": "Masharti", "footer.delete": "Futa akaunti",
    "footer.call": "Piga simu",
  },
  en: {
    "language.label": "Language",
    "language.sw": "Swahili",
    "language.en": "English",
    "nav.home": "Home",
    "nav.listings": "Listings",
    "nav.events": "Ceremonies & Events",
    "nav.referral": "Send Information",
    "nav.compare": "Compare",
    "nav.categories": "Asset categories",
    "nav.account": "Account",
    "nav.search": "Search listings",
    "auth.loading": "Loading account",
    "auth.login": "Sign in",
    "auth.register": "Register",
    "auth.account": "My Account",
    "auth.logout": "Sign out",
    "footer.tagline": "Find assets easily and connect with a verified agent.",
    "footer.body": "Browse listings, compare locations and prices, then unlock agent contact when you are ready.",
    "footer.browse": "Browse listings",
    "footer.payment": "How payment works",
    "footer.manage": "Manage: Agent, Owner & Admin",
    "footer.links": "Quick links",
    "footer.support": "Support",
    "footer.home": "Home", "footer.all": "All listings", "footer.apartments": "Apartments", "footer.houses": "Houses", "footer.cars": "Cars", "footer.compare": "Compare listings", "footer.map": "Nearby map search", "footer.advertise": "Advertise with KODIMALI", "footer.download": "Download apps", "footer.safety": "Safety", "footer.privacy": "Privacy", "footer.terms": "Terms", "footer.delete": "Delete account",
    "footer.call": "Call us",
  },
} as const;

type MessageKey = keyof typeof messages.sw;
type LanguageContextValue = { language: AppLanguage; setLanguage: (language: AppLanguage) => void; t: (key: MessageKey) => string };
const LanguageContext = createContext<LanguageContextValue | null>(null);

export function LanguageProvider({ children }: { children: ReactNode }) {
  const [language, setLanguageState] = useState<AppLanguage>("sw");

  useEffect(() => {
    const saved = window.localStorage.getItem("kodimali-language");
    const next: AppLanguage = saved === "en" ? "en" : "sw";
    setLanguageState(next);
    document.documentElement.lang = next;
  }, []);

  function setLanguage(next: AppLanguage) {
    setLanguageState(next);
    window.localStorage.setItem("kodimali-language", next);
    document.cookie = `kodimali_language=${next};path=/;max-age=31536000;samesite=lax`;
    document.documentElement.lang = next;
  }

  const value = useMemo<LanguageContextValue>(() => ({ language, setLanguage, t: (key) => messages[language][key] }), [language]);
  return <LanguageContext.Provider value={value}>{children}</LanguageContext.Provider>;
}

export function useLanguage() {
  const value = useContext(LanguageContext);
  if (!value) throw new Error("useLanguage must be used inside LanguageProvider");
  return value;
}
