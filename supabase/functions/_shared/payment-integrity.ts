import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

export type PaymentProvider = "sonicpesa" | "clickpesa";
export function paymentEvidence(provider: PaymentProvider, payload: unknown): Record<string, unknown> {
  const root = (payload && typeof payload === "object" ? payload : {}) as Record<string, unknown>;
  const row = (root.data && typeof root.data === "object" ? root.data : root) as Record<string, unknown>;
  return provider === "sonicpesa"
    ? { order_id: row.order_id, transid: row.transid, amount: row.amount, currency: row.currency, raw: root }
    : { order_id: row.orderReference, transid: row.paymentReference, amount: row.collectedAmount, currency: row.collectedCurrency, raw: root };
}
export function completePaymentEvidence(evidence: Record<string, unknown>) {
  return typeof evidence.order_id === "string" && evidence.order_id.length > 0 &&
    typeof evidence.transid === "string" && evidence.transid.length > 0 &&
    evidence.amount !== null && evidence.amount !== undefined && evidence.amount !== "" &&
    Number.isFinite(Number(evidence.amount)) && typeof evidence.currency === "string" && evidence.currency.length === 3;
}
export async function applyPaymentEvent(
  db: Pick<SupabaseClient, "rpc">, table: string, id: string,
  provider: PaymentProvider, status: string, payload: unknown,
): Promise<{ status: string; reconciliationRequired?: boolean; duplicate?: boolean }> {
  const evidence = paymentEvidence(provider, payload);
  const { data, error } = await db.rpc("apply_verified_payment_event", {
    p_table: table, p_payment_id: id, p_provider: provider, p_status: status,
    p_transaction_id: typeof evidence.transid === "string" ? evidence.transid : "",
    p_payload: evidence,
  });
  if (error) throw new Error("Payment verification is pending. Please check again shortly.");
  if (!data || typeof data.status !== "string") throw new Error("Payment verification is pending.");
  return data;
}
