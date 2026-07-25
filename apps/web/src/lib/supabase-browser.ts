import { createClient } from "@supabase/supabase-js";

const url =
  process.env.NEXT_PUBLIC_SUPABASE_URL ??
  "https://tlhoajedyaeaaqtrjqqh.supabase.co";
const publishableKey =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
  "sb_publishable_3Txem_vMHZbvLswFzjR6ng_OGXbur1K";

let browserClient: ReturnType<typeof createClient> | undefined;

export function getBrowserSupabase() {
  browserClient ??= createClient(url, publishableKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
  });
  return browserClient;
}
