// Exercise both real handlers with isolated HTTP fixtures; no account is created.
import { assertEquals } from "jsr:@std/assert@1";

import { handleRequest as createAgent } from "./create-agent-account/handler.ts";
import { handleRequest as verifyAgent } from "./verify-agent/handler.ts";
Deno.env.set("SUPABASE_URL", "https://supervisor-test.invalid");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "fixture-service-key");
const handlers = { "create-agent-account": createAgent, "verify-agent": verifyAgent };

for (const [name, handler] of Object.entries(handlers)) {
  Deno.test(`${name}: browser preflight, denied staff, and supervisor authorization`, async () => {
    const originalFetch = globalThis.fetch;
    let allowed = false;
    let admin = true;
    let mutations = 0;
    globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      const method = init?.method ?? (input instanceof Request ? input.method : "GET");
      assertEquals(url.hostname, "supervisor-test.invalid");
      const response = (body: unknown) => Promise.resolve(new Response(JSON.stringify(body), { headers: { "content-type": "application/json" } }));
      if (url.pathname === "/auth/v1/user") return response({ id: "11111111-1111-4111-8111-111111111111", aud: "authenticated" });
      if (url.pathname === "/rest/v1/user_roles") return response(admin ? [{ role: "admin" }] : []);
      if (url.pathname === "/rest/v1/rpc/has_admin_permission") {
        assertEquals(JSON.parse(String(init?.body)).p_permission, "agents.manage");
        return response(allowed);
      }
      if (method !== "GET") mutations++;
      throw new Error(`Unexpected mutation or request: ${method} ${url.pathname}`);
    }) as typeof fetch;
    try {
      let result = await handler(new Request("https://edge.invalid", { method: "OPTIONS" }));
      assertEquals(result.status, 204);
      assertEquals(result.headers.get("access-control-allow-origin"), "*");
      result = await handler(new Request("https://edge.invalid", { method: "POST" }));
      assertEquals(result.status, 401);
      const request = () => new Request("https://edge.invalid", { method: "POST", headers: { Authorization: "Bearer fixture-user", "content-type": "application/json" }, body: "{}" });
      result = await handler(request());
      assertEquals(result.status, 403); // Finance/support/unassigned staff cannot manage agents.
      allowed = true;
      admin = false;
      result = await handler(request());
      assertEquals(result.status, 403); // A customer/agent cannot become a supervisor.
      admin = true;
      result = await handler(request());
      assertEquals(result.status, 400); // Supervisor passed authorization and reached input validation.
      assertEquals(mutations, 0);
    } finally { globalThis.fetch = originalFetch; }
  });
}

Deno.test("supervisor creation validates territory and stamps protected creator metadata", async () => {
  const originalFetch = globalThis.fetch;
  const actor = "11111111-1111-4111-8111-111111111111";
  let territoryAllowed = false;
  let creations = 0;
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    assertEquals(url.hostname, "supervisor-test.invalid");
    const body = init?.body ? JSON.parse(String(init.body)) : {};
    const response = (data: unknown, status = 200) => Promise.resolve(new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } }));
    if (url.pathname === "/auth/v1/user") return response({ id: actor });
    if (url.pathname === "/rest/v1/user_roles") return response([{ role: "admin" }]);
    if (url.pathname === "/rest/v1/rpc/has_admin_permission") return response(true);
    if (url.pathname === "/rest/v1/profiles") return response([]);
    if (url.pathname === "/rest/v1/rpc/get_agent_creation_scope") return territoryAllowed ? response({ scoped: true, active: true }) : response({ message: "Choose a location inside your assigned territory" }, 403);
    if (url.pathname === "/auth/v1/admin/users") {
      assertEquals(body.app_metadata.created_by_supervisor, actor);
      creations++;
      return response({ id: "22222222-2222-4222-8222-222222222222" });
    }
    if (url.pathname === "/rest/v1/agents") return response({ id: "agent-fixture", profile_id: "22222222-2222-4222-8222-222222222222", account_status: "inactive", verification_status: "pending" });
    if (url.pathname === "/rest/v1/audit_logs") return response(null, 201);
    throw new Error("Unexpected request " + url.pathname);
  }) as typeof fetch;
  try {
    const request = () => new Request("https://edge.invalid", { method: "POST", headers: { Authorization: "Bearer fixture-user", "content-type": "application/json" }, body: JSON.stringify({ username: "fixture_agent", password: "fixture-password", full_name: "Fixture Agent", phone_number: "255700000000", location_id: "33333333-3333-4333-8333-333333333333", nida_number: "FIXTURE", business_name: "Fixture", supervisor_id: "attacker-selected-supervisor" }) });
    assertEquals((await createAgent(request())).status, 403);
    assertEquals(creations, 0);
    territoryAllowed = true;
    assertEquals((await createAgent(request())).status, 200);
    assertEquals(creations, 1);
  } finally { globalThis.fetch = originalFetch; }
});

Deno.test("supervisor cannot verify another team and own-team updates retain an ownership predicate", async () => {
  const originalFetch = globalThis.fetch;
  const actor = "11111111-1111-4111-8111-111111111111";
  let ownTeam = false;
  let updates = 0;
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    assertEquals(url.hostname, "supervisor-test.invalid");
    const response = (body: unknown) => Promise.resolve(new Response(JSON.stringify(body), { headers: { "content-type": "application/json" } }));
    if (url.pathname === "/auth/v1/user") return response({ id: actor });
    if (url.pathname === "/rest/v1/user_roles") return response([{ role: "admin" }]);
    if (url.pathname === "/rest/v1/rpc/has_admin_permission") return response(true);
    if (url.pathname === "/rest/v1/rpc/can_manage_supervised_agent") return response(ownTeam);
    if (url.pathname === "/rest/v1/rpc/get_my_supervisor_context") return response({ scoped: true, active: true });
    if (url.pathname === "/rest/v1/agents") {
      assertEquals(init?.method, "PATCH");
      assertEquals(url.searchParams.get("supervisor_id"), "eq." + actor);
      updates++;
      return response({ id: "agent-fixture", profile_id: "profile-fixture" });
    }
    if (["/rest/v1/audit_logs", "/rest/v1/notifications"].includes(url.pathname)) return response(null);
    throw new Error("Unexpected request " + url.pathname);
  }) as typeof fetch;
  try {
    const request = () => new Request("https://edge.invalid", { method: "POST", headers: { Authorization: "Bearer fixture-user", "content-type": "application/json" }, body: JSON.stringify({ agentId: "agent-fixture", accountStatus: "active", verificationStatus: "approved" }) });
    assertEquals((await verifyAgent(request())).status, 403);
    assertEquals(updates, 0);
    ownTeam = true;
    assertEquals((await verifyAgent(request())).status, 200);
    assertEquals(updates, 1);
  } finally { globalThis.fetch = originalFetch; }
});
