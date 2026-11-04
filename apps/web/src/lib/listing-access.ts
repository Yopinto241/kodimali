"use client";

import { useCallback, useEffect, useState } from "react";
import { getBrowserSupabase } from "@/lib/supabase-browser";

async function withinAccessTimeout<T>(operation: PromiseLike<T>): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {return await Promise.race([Promise.resolve(operation),new Promise<never>((_,reject)=>{timer=setTimeout(()=>reject(new Error("Access check timed out")),20000);})]);}
  finally {if(timer) clearTimeout(timer);}
}
export async function listingAccessRpc<T>(name: string, args?: Record<string, unknown>) {
  return await withinAccessTimeout(getBrowserSupabase().rpc(name,args as never)) as unknown as {data:T;error:{message:string}|null};
}

export type ListingAccess = {
  signedIn: boolean;
  chatAvailable: boolean;
  chatPrice: number | null;
  contactPrice: number | null;
  phone: string | null;
};

// Refresh on return from checkout, account changes and administrative updates.
// Unknown settings never become either a free-access promise or a payment form.
export function useListingAccess(listingId: string, kind: "chat" | "contact" = "chat") {
  const [access, setAccess] = useState<ListingAccess | null>(null);
  const [error, setError] = useState(false);
  const [revision, setRevision] = useState(0);
  const refresh = useCallback(() => setRevision((value) => value + 1), []);
  useEffect(() => {
    const db = getBrowserSupabase();
    let active = true;
    async function load() {
      try {
        if (kind === "contact") {
          const response=await fetch("/api/listing-contact-payment",{method:"POST",cache:"no-store",signal:AbortSignal.timeout(20000),headers:{"Content-Type":"application/json"},body:JSON.stringify({listing_id:listingId,quote_only:true})});
          const quote=await response.json();
          if(!response.ok || typeof quote.paymentRequired !== "boolean" || (quote.paymentRequired && (!Number.isFinite(quote.amount) || quote.amount <= 0))) throw new Error("Contact unavailable");
          if(active) {setAccess({signedIn:false,chatAvailable:false,chatPrice:null,contactPrice:quote.paymentRequired?quote.amount:0,phone:quote.paymentRequired?null:quote.phoneNumber??null});setError(false);}
          return;
        }
        const [auth, enabled, price] = await Promise.all([
          withinAccessTimeout(db.auth.getUser()), listingAccessRpc<boolean>("chat_payments_enabled"), listingAccessRpc<number>("paid_chat_unlock_price"),
        ]);
        let entitled = false;
        if (auth.data.user) {
          const result = await withinAccessTimeout(db.from("listing_chat_access").select("expires_at,revoked_at,agent_id").eq("listing_id",listingId).eq("customer_id",auth.data.user.id));
          if (result.error) throw result.error;
          const detail = await listingAccessRpc<Array<{agent_id:string}>>("get_public_listing_detail", {p_listing_id:listingId});
          if (detail.error) throw detail.error;
          const agent = detail.data?.[0]?.agent_id;
          entitled = ((result.data ?? []) as Array<{agent_id:string;revoked_at:string|null;expires_at:string}>).some(row => row.agent_id === agent && !row.revoked_at && Date.parse(row.expires_at) > Date.now());
        }
        if (!entitled && (enabled.error || typeof enabled.data !== "boolean")) throw new Error("Access unavailable");
        const chatPrice = !price.error && typeof price.data === "number" && price.data > 0 ? price.data : null;
        if (enabled.data && !entitled && chatPrice === null) throw new Error("Price unavailable");
        if (active) {
          setAccess({signedIn:!!auth.data.user, chatAvailable:enabled.data === false || entitled, chatPrice, contactPrice:null, phone:null});
          setError(false);
        }
      } catch { if (active) {setAccess(null); setError(true);} }
    }
    void load();
    const timer = window.setInterval(() => {if (document.visibilityState === "visible") void load();},30000);
    window.addEventListener("focus",refresh);
    const {data:{subscription}} = db.auth.onAuthStateChange((event) => {if (event !== "INITIAL_SESSION") {setAccess(null); refresh();}});
    return () => {active=false; window.clearInterval(timer); window.removeEventListener("focus",refresh); subscription.unsubscribe();};
  },[listingId,refresh,revision,kind]);
  return {access,error,refresh};
}
