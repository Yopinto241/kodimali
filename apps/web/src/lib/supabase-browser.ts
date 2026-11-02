import { createClient } from "@supabase/supabase-js";

const url =
  process.env.NEXT_PUBLIC_SUPABASE_URL ??
  "https://tlhoajedyaeaaqtrjqqh.supabase.co";
const publishableKey =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
  "sb_publishable_3Txem_vMHZbvLswFzjR6ng_OGXbur1K";

let browserClient: ReturnType<typeof createClient> | undefined;
let registrationClient: ReturnType<typeof createClient> | undefined;

export function getBrowserSupabase() {
  browserClient ??= createClient(url, publishableKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
  });
  return browserClient;
}

// Registration must neither overwrite an existing staff/customer session nor
// wait indefinitely on Auth or email delivery.
export function getRegistrationSupabase() {
  registrationClient ??= createClient(url, publishableKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false, storageKey: "kodimali-agent-registration" },
    global: { fetch: registrationFetch },
  });
  return registrationClient;
}

export async function registrationFetch(input: RequestInfo | URL, init?: RequestInit, timeoutMs = 20000) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeoutMs);
      const abort = () => controller.abort();
      if (init?.signal?.aborted) controller.abort();
      init?.signal?.addEventListener("abort", abort, { once: true });
      try { return await fetch(input, { ...init, signal: controller.signal }); }
      finally { clearTimeout(timer); init?.signal?.removeEventListener("abort", abort); }
}
