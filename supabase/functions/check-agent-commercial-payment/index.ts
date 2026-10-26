import { createClient } from "npm:@supabase/supabase-js@2";
import { json } from "../_shared/clickpesa.ts";
import { checkSonicPesaOrder, SonicPesaRequestError } from "../_shared/sonicpesa.ts";
Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const db = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
  try { const jwt = (request.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, ""); const { data: { user } } = await db.auth.getUser(jwt); if (!user) return json({ error: "Sign in." }, 401); const id = String((await request.json())?.payment_id ?? ""); const { data: payment } = await db.from("agent_commercial_payments").select("*,agents!inner(profile_id)").eq("id", id).single(); if (!payment || payment.agents.profile_id !== user.id) return json({ error: "Payment not found." }, 404); let status = String(payment.payment_status); if (!["paid", "failed", "expired", "cancelled"].includes(status)) { if (!payment.provider_payment_id) throw new Error("SonicPesa order is missing."); const result = await checkSonicPesaOrder(String(payment.provider_payment_id)); status = result.status; await db.from("agent_commercial_payments").update({ payment_status: status, paid_at: status === "paid" ? new Date().toISOString() : null, provider_payment_reference: result.transactionId, provider_channel: result.channel, provider_response: result.payload }).eq("id", id); } return json({ success: true, paymentStatus: status, amount: payment.requested_amount }); }
  catch (error) { return json({ error: error instanceof Error ? error.message : "Could not check payment." }, error instanceof SonicPesaRequestError ? error.status : 500); }
});
