// Audit probes assert existing defects. All HTTP is intercepted; no live writes.
import { assertEquals } from "jsr:@std/assert@1";

type Handler = (request: Request) => Promise<Response>;
async function fixture(name: string, inspect: (url: URL, init?: RequestInit) => unknown, test: (handler: Handler) => Promise<void>) {
  const originalFetch = globalThis.fetch;
  const originalServe = Deno.serve;
  const originals = new Map<string, string | undefined>();
  for (const [key, value] of Object.entries({ SUPABASE_URL: "https://audit.invalid", SUPABASE_SERVICE_ROLE_KEY: "fixture-key", SONICPESA_WEBHOOK_SECRET: "fixture-secret" })) {
    originals.set(key, Deno.env.get(key)); Deno.env.set(key, value);
  }
  let handler: Handler | undefined;
  Object.defineProperty(Deno, "serve", { configurable: true, writable: true, value: (fn: Handler) => { handler = fn; } });
  globalThis.fetch = (input, init) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    if (url.hostname !== "audit.invalid") throw new Error("Unexpected external network access");
    return Promise.resolve(new Response(JSON.stringify(inspect(url, init)), { status: 200, headers: { "Content-Type": "application/json" } }));
  };
  try {
    await import(`../supabase/functions/${name}/index.ts?audit=${crypto.randomUUID()}`);
    if (!handler) throw new Error("Handler was not captured");
    await test(handler);
  } finally {
    globalThis.fetch = originalFetch;
    Object.defineProperty(Deno, "serve", { configurable: true, writable: true, value: originalServe });
    for (const [key, value] of originals) { if (value === undefined) Deno.env.delete(key); else Deno.env.set(key, value); }
  }
}
async function signed(body: Record<string, unknown>) {
  const raw = JSON.stringify(body);
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode("fixture-secret"), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const bytes = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(raw)));
  const signature = [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
  return new Request("https://fixture.invalid", { method: "POST", body: raw, headers: { "x-sonicpesa-signature": signature } });
}
Deno.test("REPRODUCED: unauthenticated notification dispatch performs service-role writes", async () => {
  let writes = 0;
  await fixture("dispatch-push-notifications", (_url, init) => { if (init?.method === "PATCH") writes++; return []; }, async (handler) => {
    const response = await handler(new Request("https://fixture.invalid", { method: "POST" }));
    assertEquals(response.status, 200);
    assertEquals(writes, 2);
  });
});
Deno.test("REPRODUCED: late processing webhook overwrites an already paid platform order", async () => {
  let patch: Record<string, unknown> | undefined;
  await fixture("sonicpesa-payment-webhook", (url, init) => {
    if (url.pathname.endsWith("claim_payment_webhook_event")) return true;
    if (url.pathname.endsWith("finish_payment_webhook_event")) return null;
    if (init?.method === "PATCH") { patch = JSON.parse(String(init.body)); return null; }
    if (url.pathname.endsWith("platform_payment_orders")) return { id: "fixture", amount_tzs: 1000, currency: "TZS", status: "paid" };
    throw new Error("Unexpected request " + url.pathname);
  }, async (handler) => {
    assertEquals((await handler(await signed({ order_id: "fixture", transid: "fixture", event: "payment.processing", status: "INPROGRESS" }))).status, 200);
    assertEquals(patch?.status, "processing");
  });
});
Deno.test("REPRODUCED: successful platform webhook without amount still calls financial finalization", async () => {
  let finalized = false;
  await fixture("sonicpesa-payment-webhook", (url) => {
    if (url.pathname.endsWith("claim_payment_webhook_event")) return true;
    if (url.pathname.endsWith("finish_payment_webhook_event")) return null;
    if (url.pathname.endsWith("finalize_platform_payment")) { finalized = true; return null; }
    if (url.pathname.endsWith("platform_payment_orders")) return { id: "fixture", amount_tzs: 100000, currency: "TZS", status: "pending" };
    throw new Error("Unexpected request " + url.pathname);
  }, async (handler) => {
    assertEquals((await handler(await signed({ order_id: "fixture", transid: "fixture", status: "SUCCESS" }))).status, 200);
    assertEquals(finalized, true);
  });
});
