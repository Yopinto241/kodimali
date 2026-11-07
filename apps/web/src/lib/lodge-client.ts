import type { SupabaseClient } from "@supabase/supabase-js";
import { getBrowserSupabase } from "./supabase-browser";
import type { LodgeRow } from "./lodge-forms";
type LodgeDatabase = {
  public: {
    Tables: Record<string, never>;
    Views: Record<string, never>;
    Functions: Record<string, { Args: LodgeRow; Returns: unknown }>;
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};
export function getLodgeClient() {
  return getBrowserSupabase() as unknown as SupabaseClient<LodgeDatabase>;
}
