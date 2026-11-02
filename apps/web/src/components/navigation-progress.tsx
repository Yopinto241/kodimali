"use client";
import { UiText } from "@/components/ui-text";

import { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";
import { useLanguage } from "@/components/language-provider";

const NavigationContext = createContext<(href: string) => void>(() => {});

export function NavigationIndicator({ inline = false }: { inline?: boolean }) {
  const { language } = useLanguage();
  return (
    <div className={inline ? 'navigation-progress-inline' : 'navigation-progress'} role="status" aria-live="polite">
      <div className="navigation-progress-card">
        <span className="navigation-progress-icon" aria-hidden="true">
          <span className="navigation-progress-empty" />
          <span className="navigation-progress-fill" />
        </span>
        <span><UiText text={language === "sw" ? "Inafungua..." : "Loading..."} /></span>
      </div>
    </div>
  );
}

export function NavigationProgress({ children }: { children: React.ReactNode }) {
  const [pending, setPending] = useState(false);
  const leaving = useRef(false);
  const navigate = useCallback((href: string) => {
    const destination = new URL(href, window.location.href);
    if (destination.origin !== window.location.origin || !["http:", "https:"].includes(destination.protocol)) return;
    if (destination.pathname === window.location.pathname && destination.search === window.location.search) {
      if (destination.hash) window.location.hash = destination.hash;
      return;
    }
    if (leaving.current) return;
    leaving.current = true;
    setPending(true);
    // A document request keeps the destination and its scripts on the same release.
    // No retry timer: cached pages can open immediately.
    window.location.assign(destination.href);
  }, []);

  useEffect(() => {
    function onClick(event: MouseEvent) {
      if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      const anchor = event.target instanceof Element ? event.target.closest("a[href]") : null;
      if (!(anchor instanceof HTMLAnchorElement) || anchor.hasAttribute("download") || (anchor.target && anchor.target !== "_self") || anchor.rel.split(" ").includes("external")) return;
      const url = new URL(anchor.href, window.location.href);
      if (url.origin !== window.location.origin || !["http:", "https:"].includes(url.protocol)) return;
      // Leave downloads, API calls, and same-page anchors to the browser.
      if (url.pathname.startsWith("/api/") || /\.[a-z0-9]+$/i.test(url.pathname)) return;
      if (url.pathname === window.location.pathname && url.search === window.location.search) return;
      event.preventDefault();
      navigate(`${url.pathname}${url.search}${url.hash}`);
    }
    const restore = () => { leaving.current = false; setPending(false); };
    document.addEventListener("click", onClick, true);
    window.addEventListener("pageshow", restore);
    return () => { document.removeEventListener("click", onClick, true); window.removeEventListener("pageshow", restore); };
  }, [navigate]);

  return <NavigationContext.Provider value={navigate}>{children}{pending ? <NavigationIndicator /> : null}</NavigationContext.Provider>;
}

export function useNavigate() {
  return useContext(NavigationContext);
}
