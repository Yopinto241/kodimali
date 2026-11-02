import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

const agent = "00000000-0000-4000-8000-000000000001";
const listing = "00000000-0000-4000-8000-000000000011";
async function invokeFixture(name: string, fee: number | null, signedIn = true, ownsResource = true) {
  const originalFetch = globalThis.fetch;
  const originalServe = Deno.serve;
  const originalUrl = Deno.env.get("SUPABASE_URL");
  const originalKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  let handler: ((request: Request) => Promise<Response>) | undefined;
  const calls: string[] = [];
  Deno.env.set("SUPABASE_URL", "http://127.0.0.1:9999");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "fixture-only");
  Object.defineProperty(Deno, "serve", { configurable: true, writable: true, value: (callback: typeof handler) => { handler = callback; } });
  globalThis.fetch = async (input) => {
    const url = String(input instanceof Request ? input.url : input);
    calls.push(url);
    let data: unknown;
    if (url.includes("/auth/v1/user")) {
      if (!signedIn) return new Response(JSON.stringify({ message: "Invalid session" }), { status: 401, headers: { "Content-Type": "application/json" } });
      data = { id: agent, aud: "authenticated", role: "authenticated" };
    }
    else if (url.includes("/rest/v1/agents?")) data = { id: agent, verification_status: "approved", phone_number: "255700000000" };
    else if (url.includes("/rest/v1/listings?")) data = ownsResource ? { id: listing, status: "inactive", agent_id: agent } : null;
    else if (url.includes("/rest/v1/agent_listing_payments?")) data = ownsResource ? { id: listing, listing_id: listing, payment_status: "pending", provider_payment_id: "sp_fixture", order_reference: "fixture" } : null;
    else if (url.endsWith("/rpc/agent_listing_publication_fee")) data = fee;
    else if (url.endsWith("/rpc/assert_agent_plan_listing_capacity")) data = null;
    else if (url.endsWith("/rpc/release_agent_listing_if_eligible")) data = true;
    else throw new Error(`Unexpected external request: ${url}`);
    return new Response(JSON.stringify(data), { headers: { "Content-Type": "application/json" } });
  };
  try {
    await import(`../supabase/functions/${name}/index.ts?fixture=${crypto.randomUUID()}`);
    if (!handler) throw new Error("Missing handler");
    const response = await handler(new Request("http://fixture.invalid", { method: "POST", headers: { Authorization: "Bearer fixture", "Content-Type": "application/json" }, body: JSON.stringify({ listing_id: listing, payment_id: listing }) }));
    return { status: response.status, body: await response.json(), calls };
  } finally {
    globalThis.fetch = originalFetch;
    Object.defineProperty(Deno, "serve", { configurable: true, writable: true, value: originalServe });
    if (originalUrl === undefined) Deno.env.delete("SUPABASE_URL"); else Deno.env.set("SUPABASE_URL", originalUrl);
    if (originalKey === undefined) Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY"); else Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", originalKey);
  }
}
for (const name of ["create-agent-listing-payment", "check-agent-listing-payment"]) {
  Deno.test(`${name}: invalid session is denied before any database access`, async () => {
    const result = await invokeFixture(name, 0, false);
    assertEquals(result.status, 401);
    assertEquals(result.calls.some((url) => url.includes("/rest/v1/")), false);
  });
  Deno.test(`${name}: another agent's listing or payment cannot be published`, async () => {
    const result = await invokeFixture(name, 0, true, false);
    assertEquals(result.status, name.startsWith("create") ? 403 : 404);
    assertEquals(result.calls.some((url) => url.endsWith("release_agent_listing_if_eligible")), false);
  });
  Deno.test(`${name}: free fee releases without contacting a payment provider`, async () => {
    const result = await invokeFixture(name, 0);
    assertEquals(result.status, 200);
    assertEquals(result.body.paymentRequired, false);
    assertEquals(result.body.paymentStatus, "free");
    assertEquals(result.body.published, true);
    assertEquals(result.calls.some((url) => !url.startsWith("http://127.0.0.1:9999/")), false);
  });
  Deno.test(`${name}: missing effective fee fails closed`, async () => {
    const result = await invokeFixture(name, null);
    assertEquals(result.status, 500);
    assertEquals(result.calls.some((url) => url.endsWith("release_agent_listing_if_eligible")), false);
  });
}
