// Optional UI preferences must never prevent browsing.
export const browserPreferences = {
  getItem(key: string): string | null { try { return window.localStorage.getItem(key); } catch { return null; } },
  setItem(key: string, value: string): boolean { try { window.localStorage.setItem(key, value); return true; } catch { return false; } },
  removeItem(key: string): void { try { window.localStorage.removeItem(key); } catch { /* Optional preference. */ } },
};
export function readStoredIds(key: string): string[] {
  try { const value: unknown = JSON.parse(browserPreferences.getItem(key) ?? "[]"); return Array.isArray(value) ? value.filter((id): id is string => typeof id === "string") : []; } catch { return []; }
}
