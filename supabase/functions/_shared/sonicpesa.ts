export class SonicPesaRequestError extends Error {
  constructor(message: string, public status = 500, public payload?: unknown) {
    super(message);
    this.name = "SonicPesaRequestError";
  }
}

export type SonicPesaStatus = "pending" | "processing" | "paid" | "cancelled" | "failed";

export function useSonicPesa(): boolean {
  return (Deno.env.get("PAYMENT_PROVIDER") ?? "clickpesa").trim().toLowerCase() === "sonicpesa";
}

function config() {
  const apiKey = (Deno.env.get("SONICPESA_API_KEY") ?? "").trim();
  const baseUrl = (Deno.env.get("SONICPESA_API_BASE_URL") ?? "https://api.sonicpesa.com/api/v1").replace(/\/$/, "");
  if (!apiKey) throw new SonicPesaRequestError("SonicPesa is not configured. Add SONICPESA_API_KEY to Supabase function secrets.", 503);
  return { apiKey, baseUrl };
}

async function post(path: string, body: Record<string, unknown>): Promise<Record<string, unknown>> {
  const { apiKey, baseUrl } = config();
  const response = await fetch(`${baseUrl}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-API-KEY": apiKey }, body: JSON.stringify(body) });
  const payload = await response.json().catch(() => ({})) as Record<string, unknown>;
  if (!response.ok || String(payload.status ?? "").toLowerCase() === "error") {
    throw new SonicPesaRequestError(String(payload.message ?? "SonicPesa could not process the request."), response.status, payload);
  }
  return payload;
}

export async function createSonicPesaOrder(input: { phone: string; amount: number; email?: string; name?: string }) {
  const buyerEmail = input.email?.trim() ||
    (Deno.env.get("SONICPESA_BUYER_EMAIL") ?? "payments@kodimali.co.tz").trim();
  const payload = await post("/payment/create_order", { buyer_phone: input.phone, buyer_email: buyerEmail, buyer_name: input.name || "KODIMALI customer", amount: input.amount, currency: "TZS" });
  const data = (payload.data ?? {}) as Record<string, unknown>;
  const orderId = String(data.order_id ?? "");
  if (!orderId) throw new SonicPesaRequestError("SonicPesa returned an invalid order response.", 502, payload);
  return { orderId, status: mapSonicPesaStatus(data.payment_status ?? data.status), channel: typeof data.channel === "string" ? data.channel : null, payload };
}

export async function checkSonicPesaOrder(orderId: string) {
  const payload = await post("/payment/order_status", { order_id: orderId });
  const data = (payload.data ?? {}) as Record<string, unknown>;
  return { orderId: String(data.order_id ?? orderId), status: mapSonicPesaStatus(data.payment_status ?? data.status), transactionId: typeof data.transid === "string" ? data.transid : null, channel: typeof data.channel === "string" ? data.channel : null, payload };
}

export function mapSonicPesaStatus(value: unknown): SonicPesaStatus {
  switch (String(value ?? "").toUpperCase()) {
    case "SUCCESS": return "paid";
    case "INPROGRESS": return "processing";
    case "CANCELLED": case "USERCANCELLED": return "cancelled";
    case "REJECTED": return "failed";
    default: return "pending";
  }
}
