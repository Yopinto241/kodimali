"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import type { User } from "@supabase/supabase-js";

import { getBrowserSupabase } from "@/lib/supabase-browser";
import { useLanguage } from "@/components/language-provider";

export function AuthActions({ mobile = false }: { mobile?: boolean }) {
  const { t } = useLanguage();
  const supabase = getBrowserSupabase();
  const [user, setUser] = useState<User | null | undefined>(undefined);

  useEffect(() => {
    let active = true;
    void supabase.auth.getUser().then(({ data }) => {
      if (active) setUser(data.user);
    });
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      if (active) setUser(session?.user ?? null);
    });
    return () => {
      active = false;
      data.subscription.unsubscribe();
    };
  }, [supabase]);

  const layout = mobile ? "contents" : "hidden items-center gap-2 sm:flex";
  if (user === undefined) {
    return <span className={mobile ? "h-10 w-24 shrink-0 rounded-full bg-brand-card-soft" : "hidden h-10 w-24 rounded-full bg-brand-card-soft sm:block"} aria-label={t("auth.loading")} />;
  }
  if (!user) {
    return (
      <div className={layout}>
        <Link href="/login" className="btn btn-outline shrink-0">{t("auth.login")}</Link>
        <Link href="/register" className="btn btn-success shrink-0">{t("auth.register")}</Link>
      </div>
    );
  }
  return (
    <div className={layout}>
      <Link href="/account" className="btn btn-success shrink-0">{t("auth.account")}</Link>
      <button
        className="btn btn-outline shrink-0"
        type="button"
        onClick={() => void supabase.auth.signOut().then(() => window.location.assign("/"))}
      >
        {t("auth.logout")}
      </button>
    </div>
  );
}
