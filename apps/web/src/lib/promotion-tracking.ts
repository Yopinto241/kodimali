import { getBrowserSupabase } from "./supabase-browser";
let memorySession: string | undefined;
export function promotionSession() {
  if (memorySession) return memorySession;
  try { memorySession = window.sessionStorage.getItem("kodimali-ad-session") ?? undefined; } catch { /* Optional analytics storage. */ }
  memorySession ??= typeof crypto.randomUUID === "function" ? crypto.randomUUID() : `ad-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  try { window.sessionStorage.setItem("kodimali-ad-session", memorySession); } catch { /* Memory fallback. */ }
  return memorySession;
}
export function recordPromotion(id: string, event: "impression" | "click") {
  try { void Promise.resolve(getBrowserSupabase().rpc("record_platform_promotion_event", { p_promotion_id: id, p_event_type: event, p_surface: "website", p_session_key: promotionSession() } as never)).catch(() => {}); } catch { /* Advertising must never interrupt browsing. */ }
}
export function promotionDestination(value?: string | null) {
  if (!value) return "/listings";
  try {
    const url = new URL(value, "https://kodimali.com");
    if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) return "/listings";
    return ["kodimali.com", "www.kodimali.com"].includes(url.hostname) ? `${url.pathname}${url.search}${url.hash}` : url.href;
  } catch { return "/listings"; }
}
