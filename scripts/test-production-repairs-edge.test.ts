import { readClickPesaConfig } from "../supabase/functions/_shared/clickpesa.ts";
// Repair regressions. All network access is intercepted; no production calls.
import { assertEquals } from "jsr:@std/assert@1";

type Handler = (request: Request) => Promise<Response>;
async function fixture(name: string, inspect: (url: URL, init?: RequestInit) => unknown, test: (handler: Handler) => Promise<void>) {
  const originalFetch = globalThis.fetch;
  const originalServe = Deno.serve;
  const originals = new Map<string, string | undefined>();
  for (const [key, value] of Object.entries({ SUPABASE_URL: "https://audit.invalid", SUPABASE_SERVICE_ROLE_KEY: "fixture-key", SUPABASE_ANON_KEY:"fixture-anon-key", SONICPESA_WEBHOOK_SECRET: "fixture-secret", CLICKPESA_COLLECTION_CLIENT_ID:"fixture", CLICKPESA_COLLECTION_API_KEY:"fixture", CLICKPESA_COLLECTION_CHECKSUM_KEY:"fixture-checksum" })) {
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

Deno.test("F03/F06 public requests cannot invoke internal workers", async () => {
  for (const name of ["dispatch-push-notifications","notify-agent","mark-agent-delayed"]) {
    let calls=0;
    await fixture(name,()=>{calls++;return [];},async handler=>{
      for (const headers of <Record<string,string>[]>[{},{Authorization:"Bearer frontend-anon-key"},{"x-kodimali-worker-secret":"wrong"}]) {
        const response=await handler(new Request("https://fixture.invalid",{method:"POST",headers,body:"{}"}));
        assertEquals(response.status,401);
      }
      assertEquals(calls,0);
    });
  }
});
Deno.test("F04 late processing webhook uses atomic path and preserves persisted paid state",async()=>{
  let applied=false;
  await fixture("sonicpesa-payment-webhook",(url,init)=>{
    if (url.pathname.endsWith("claim_payment_webhook_event")) return true;
    if (url.pathname.endsWith("finish_payment_webhook_event")) return null;
    if (url.pathname.endsWith("platform_payment_orders")) return {id:"fixture"};
    if (url.pathname.endsWith("apply_verified_payment_event")) {
      const args=JSON.parse(String(init?.body));assertEquals(args.p_status,"processing");applied=true;return {status:"paid",duplicate:true};
    }
    throw new Error("Unexpected mutation: "+url.pathname);
  },async handler=>{assertEquals((await handler(await signed({order_id:"fixture",transid:"fixture",status:"INPROGRESS"}))).status,200);assertEquals(applied,true);});
});
Deno.test("F05 incomplete success reaches reconciliation without direct finalization",async()=>{
  let applied=false;
  await fixture("sonicpesa-payment-webhook",(url,init)=>{
    if (url.pathname.endsWith("claim_payment_webhook_event")) return true;
    if (url.pathname.endsWith("finish_payment_webhook_event")) return null;
    if (url.pathname.endsWith("platform_payment_orders")) return {id:"fixture"};
    if (url.pathname.endsWith("apply_verified_payment_event")) {
      const args=JSON.parse(String(init?.body));assertEquals(args.p_payload.amount,undefined);assertEquals(args.p_payload.currency,undefined);applied=true;return {status:"reconciliation_required",reconciliationRequired:true};
    }
    throw new Error("Unexpected financial mutation: "+url.pathname);
  },async handler=>{const response=await handler(await signed({order_id:"fixture",transid:"fixture",status:"SUCCESS"}));assertEquals(response.status,200);assertEquals((await response.json()).reconciliationRequired,true);assertEquals(applied,true);});
});
Deno.test("F06 staff without bookings.manage cannot mutate booking",async()=>{
  let writes=0;
  await fixture("update-booking-status",(url,init)=>{
    if (["PATCH","POST"].includes(init?.method??"")&&!url.pathname.includes("/rpc/has_admin_permission")) writes++;
    if (url.pathname.endsWith("/user")) return {id:"analyst"};
    if (url.pathname.endsWith("booking_requests")) return {id:"booking",agent_id:"assigned",customer_id:"customer"};
    if (url.pathname.endsWith("has_admin_permission")) return false;
    return null;
  },async handler=>{const response=await handler(new Request("https://fixture.invalid",{method:"POST",headers:{Authorization:"Bearer fixture-session","Content-Type":"application/json"},body:JSON.stringify({bookingRequestId:"booking",nextStatus:"confirmed"})}));assertEquals(response.status,403);assertEquals(writes,0);});
});

Deno.test("ClickPesa unsigned and invalid checksum events cannot read or mutate payments",async()=>{
  let calls=0;
  await fixture("clickpesa-payment-webhook",()=>{calls++;return null;},async handler=>{
    for (const checksum of [undefined,"invalid"]) {
      const response=await handler(new Request("https://fixture.invalid",{method:"POST",body:JSON.stringify({checksum,data:{orderReference:"FIXTURE",status:"SUCCESS"}})}));
      assertEquals(response.status,401);
    }
    assertEquals(calls,0);
  });
});
Deno.test("disabled booking and event collections cannot create an order",async()=>{
  for (const [name,products] of [["create-booking-payment",["booking_deposit","booking_balance"]],["create-platform-payment",["event_deposit","event_balance"]]] as const) {
    await fixture(name,(url)=>{
      if (url.pathname.endsWith("/user")) return {id:"fixture-customer"};
      if (url.pathname.endsWith("payment_feature_enabled")) return false;
      throw new Error("Disabled product accessed a provider or created an order");
    },async handler=>{
      for (const product of products) {
        const body={purpose:product,product,booking_id:"fixture",resource_id:"fixture",phone_number:"255700000000",idempotency_key:"fixture-idempotency-key"};
        const response=await handler(new Request("https://fixture.invalid",{method:"POST",headers:{Authorization:"Bearer fixture-session"},body:JSON.stringify(body)}));
        assertEquals(response.status,503);
      }
    });
  }
});

Deno.test("existing protected checksum SECRET name is supported with explicit KEY precedence",()=>{
  const names=["CLICKPESA_COLLECTION_CLIENT_ID","CLICKPESA_COLLECTION_API_KEY","CLICKPESA_COLLECTION_CHECKSUM_KEY","CLICKPESA_COLLECTION_CHECKSUM_SECRET"];
  const previous=new Map(names.map(name=>[name,Deno.env.get(name)]));
  try {
    Deno.env.set(names[0],"fixture-client");Deno.env.set(names[1],"fixture-api");
    Deno.env.delete(names[2]);Deno.env.set(names[3],"fixture-existing-checksum");
    const options={clientIdEnv:names[0],apiKeyEnv:names[1],checksumKeyEnv:names[2]};
    assertEquals(readClickPesaConfig(options).checksumKey,"fixture-existing-checksum");
    Deno.env.set(names[2],"fixture-explicit-checksum");
    assertEquals(readClickPesaConfig(options).checksumKey,"fixture-explicit-checksum");
    Deno.env.delete(names[2]);Deno.env.delete(names[3]);
    assertEquals(readClickPesaConfig(options).checksumKey,null);
  } finally {for(const [name,value] of previous) {if(value===undefined) Deno.env.delete(name);else Deno.env.set(name,value);}}
});

Deno.test("contact quote and free access require no personal details and never create orders",async()=>{
  for(const enabled of [false,true]) {
    await fixture("create-listing-contact-payment",url=>{
      if(url.pathname.endsWith("/listings")) return {id:"listing",agent_id:"agent",asset_categories:{slug:"house"}};
      if(url.pathname.endsWith("/agents")) return {id:"agent",phone_number:"255700000000"};
      if(url.pathname.endsWith("/contact_payments_enabled")) return enabled;
      if(url.pathname.endsWith("/is_listing_public")) return true;
      throw new Error("Quote/free contact attempted a payment or unrelated database operation");
    },async handler=>{
      const response=await handler(new Request("https://fixture.invalid",{method:"POST",body:JSON.stringify({listing_id:"listing",quote_only:true})}));
      assertEquals(response.status,200);const body=await response.json();
      assertEquals(body.paymentRequired,enabled);
      assertEquals(body.phoneNumber,enabled?undefined:"255700000000");
      if(enabled) assertEquals(body.amount>0,true);
    });
  }
});
Deno.test("contact fee change rejects before saving or sending a payment",async()=>{
  await fixture("create-listing-contact-payment",url=>{
    if(url.pathname.endsWith("/listings")) return {id:"listing",agent_id:"agent",asset_categories:{slug:"house"}};
    if(url.pathname.endsWith("/agents")) return {id:"agent",phone_number:"255700000000"};
    if(url.pathname.endsWith("/contact_payments_enabled")) return true;
    if(url.pathname.endsWith("/is_listing_public")) return true;
    throw new Error("Changed quote attempted an order");
  },async handler=>{
    const response=await handler(new Request("https://fixture.invalid",{method:"POST",body:JSON.stringify({listing_id:"listing",customer_name:"Test User",customer_phone_number:"255700000000",expected_amount:1})}));assertEquals(response.status,409);
  });
});
Deno.test("existing chat access bypasses phone validation and never creates another order",async()=>{
  await fixture("create-listing-chat-payment",url=>{
    if(url.pathname.endsWith("/user")) return {id:"customer"};
    if(url.pathname.endsWith("/listings")) return {id:"listing",agent_id:"agent"};
    if(url.pathname.endsWith("/is_listing_public")) return true;
    if(url.pathname.endsWith("/chat_payments_enabled")) return true;
    if(url.pathname.endsWith("/paid_chat_unlock_price")) return 1000;
    if(url.pathname.endsWith("/listing_chat_access")) return {expires_at:"2099-01-01T00:00:00Z"};
    throw new Error("Existing access attempted another payment");
  },async handler=>{
    const response=await handler(new Request("https://fixture.invalid",{method:"POST",headers:{Authorization:"Bearer fixture"},body:JSON.stringify({listing_id:"listing",phone_number:""})}));assertEquals(response.status,200);assertEquals((await response.json()).paymentRequired,false);
  });
});
