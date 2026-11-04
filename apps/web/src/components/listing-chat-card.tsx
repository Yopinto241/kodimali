"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useNavigate } from "@/components/navigation-progress";
import { useLanguage } from "@/components/language-provider";
import { getBrowserSupabase } from "@/lib/supabase-browser";
import { listingAccessRpc, useListingAccess } from "@/lib/listing-access";
import { safeUserMessage } from "@/lib/user-message";

type Row = Record<string, unknown>;
export function ListingChatCard({listingId}:{listingId:string}) {
  const {language}=useLanguage(); const sw=language==="sw";
  const {access,error,refresh}=useListingAccess(listingId);
  const navigate=useNavigate(); const attempted=useRef(false);
  const [phone,setPhone]=useState(""); const [paymentId,setPaymentId]=useState<string|null>(null);
  const [busy,setBusy]=useState(false); const [notice,setNotice]=useState("");
  const open=useCallback(async()=>{
    const {data,error}=await listingAccessRpc<Row|Row[]>("get_or_create_listing_conversation",{p_listing_id:listingId});
    if(error) throw error;
    const row=(Array.isArray(data)?data[0]:data) as Row|null;
    if(!row?.id) throw new Error("The chat could not be opened.");
    navigate(`/account/chat/${String(row.id)}`);
  },[listingId,navigate]);
  const start=useCallback(async()=>{
    if(!access || !access.signedIn) return;
    setBusy(true); setNotice("");
    try {
      const {data,error}=await getBrowserSupabase().functions.invoke("create-listing-chat-payment",{body:{listing_id:listingId,phone_number:phone.trim(),...(access.chatAvailable?{}:{expected_amount:access.chatPrice})}});
      if(error) throw error;
      if(data?.paymentRequired===false || data?.paymentStatus==="paid") {await open();return;}
      if(!data?.paymentId) throw new Error("Payment could not be started.");
      setPaymentId(String(data.paymentId)); setNotice(sw?"Thibitisha ombi la malipo kwenye simu yako.":"Approve the payment request on your phone. Chat will open after confirmation.");
    } catch(error) {setNotice(safeUserMessage(error));refresh();}
    finally {setBusy(false);}
  },[access,listingId,open,phone,refresh,sw]);
  useEffect(()=>{
    if(!access?.signedIn || !access.chatAvailable || attempted.current) return;
    attempted.current=true; void start();
  },[access,start]);
  const check=useCallback(async()=>{
    if(!paymentId) return;
    try {
      const {data,error}=await getBrowserSupabase().functions.invoke("check-listing-chat-payment",{body:{payment_id:paymentId}});
      if(error) throw error;
      if(data?.paymentStatus==="paid") {await open();return;}
      if(["failed","expired","cancelled"].includes(data?.paymentStatus)) {
        setPaymentId(null);setNotice(sw?"Malipo hayajakamilika. Unaweza kujaribu tena.":"Payment was not completed. You can try again.");refresh();
      }
    } catch(error) {setNotice(safeUserMessage(error));}
  },[paymentId,open,refresh,sw]);
  useEffect(()=>{if(!paymentId) return; const timer=window.setInterval(()=>void check(),6000);return()=>window.clearInterval(timer);},[paymentId,check]);
  return <section className="surface-card rounded-[20px] p-5 sm:p-6" aria-busy={busy}>
    <h2 className="font-heading text-xl font-semibold">{sw?"Zungumza na wakala":"Chat with the agent"}</h2>
    <p className="mt-2 text-sm text-muted">{sw?"Uliza kuhusu mali hii na upange hatua inayofuata na wakala.":"Ask about this listing and make arrangements with the agent."}</p>
    {!access ? <div className="mt-5" role="status">{error?<><p>{sw?"Imeshindikana kuangalia ruhusa kwa sasa.":"Access could not be checked right now."}</p><button className="btn btn-outline mt-3" onClick={refresh}>{sw?"Jaribu tena":"Try again"}</button></>:<p>{sw?"Inaangalia ruhusa...":"Checking access..."}</p>}</div>:
      !access.signedIn?<Link className="btn btn-success mt-5" href={`/login?next=${encodeURIComponent(`/listing/${listingId}/chat`)}`}>{sw?"Ingia ili kuzungumza":"Sign in to chat"}</Link>:
      access.chatAvailable?<button className="btn btn-success mt-5" disabled={busy} onClick={()=>void start()}>{busy?(sw?"Inafungua...":"Opening chat..."):(sw?"Zungumza hapa":"Chat here")}</button>:
      paymentId?<div className="mt-5"><p className="text-sm">{sw?"Inasubiri uthibitisho wa malipo.":"Waiting for payment confirmation."}</p><button className="btn btn-outline mt-3" onClick={()=>void check()}>{sw?"Angalia hali":"Check status"}</button></div>:
      <form className="mt-5 grid gap-4" onSubmit={event=>{event.preventDefault();void start();}}>
        <p className="font-semibold">TZS {access.chatPrice?.toLocaleString()} <span className="text-sm font-normal text-muted">{sw?"kwa siku 7":"for 7 days"}</span></p>
        <label className="grid gap-2 text-sm font-semibold">{sw?"Namba ya malipo ya simu":"Mobile-money number"}<input className="field-input" type="tel" autoComplete="tel" placeholder="2557XXXXXXXX" value={phone} onChange={event=>setPhone(event.target.value)} required /></label>
        <button className="btn btn-success" disabled={busy}>{busy?(sw?"Inatuma ombi...":"Sending request..."):(sw?`Lipa TZS ${access.chatPrice?.toLocaleString()} na uendelee`:`Pay TZS ${access.chatPrice?.toLocaleString()} and continue`)}</button>
      </form>}
    {notice?<p className="mt-4 text-sm text-muted" role="status">{notice}</p>:null}
  </section>;
}
