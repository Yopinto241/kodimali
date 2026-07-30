import { createClient } from "npm:@supabase/supabase-js@2";
import { ClickPesaRequestError, createChecksum, fetchClickPesaToken, formatAmount, initiateUssdPushRequest, json, mapClickPesaStatus, normalizePhoneNumber, previewUssdPushRequest, readClickPesaConfig } from "../_shared/clickpesa.ts";
const AMOUNT = 500;
const reference = () => `CH${crypto.randomUUID().replaceAll("-", "").slice(0, 18).toUpperCase()}`;
Deno.serve(async (request) => {
  if (request.method !== "POST") return json({error:"Method not allowed"},405);
  const db=createClient(Deno.env.get("SUPABASE_URL")??"",Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")??"");
  try {
    const jwt=(request.headers.get("Authorization")??"").replace(/^Bearer\s+/i,"");
    const {data:{user}}=await db.auth.getUser(jwt); if(!user)return json({error:"Sign in to open a private chat."},401);
    const body=await request.json(); const listingId=String(body?.listing_id??"").trim(); const phone=normalizePhoneNumber(String(body?.phone_number??""));
    const {data:listing}=await db.from("listings").select("id,agent_id").eq("id",listingId).single();
    const {data:isPublic}=await db.rpc("is_listing_public",{p_listing_id:listingId});
    if(!listing||isPublic!==true)return json({error:"This listing is not available for chat."},404);
    const {data:enabled,error:settingsError}=await db.rpc("chat_payments_enabled"); if(settingsError)throw new Error(settingsError.message);
    if(enabled===false){
      const now=new Date(); const expires=new Date(now.getTime()+7*86400000);
      await db.from("listing_chat_access").upsert({listing_id:listingId,agent_id:listing.agent_id,customer_id:user.id,access_source:"free",starts_at:now.toISOString(),expires_at:expires.toISOString(),revoked_at:null},{onConflict:"customer_id,listing_id,agent_id"});
      return json({success:true,paymentRequired:false,paymentStatus:"paid",expiresAt:expires.toISOString()});
    }
    if(phone.length<12)return json({error:"Enter a valid mobile-money phone number."},400);
    const {data:access}=await db.from("listing_chat_access").select("expires_at").eq("listing_id",listingId).eq("customer_id",user.id).gt("expires_at",new Date().toISOString()).maybeSingle();
    if(access)return json({success:true,paymentRequired:false,paymentStatus:"paid",expiresAt:access.expires_at});
    const config=readClickPesaConfig({clientIdEnv:"CLICKPESA_COLLECTION_CLIENT_ID",apiKeyEnv:"CLICKPESA_COLLECTION_API_KEY",checksumKeyEnv:"CLICKPESA_COLLECTION_CHECKSUM_KEY"});
    const orderReference=reference(); const payload:Record<string,unknown>={amount:formatAmount(AMOUNT),currency:"TZS",orderReference,phoneNumber:phone}; if(config.checksumKey)payload.checksum=createChecksum(config.checksumKey,payload);
    const {data:payment,error}=await db.from("listing_chat_payments").insert({listing_id:listingId,agent_id:listing.agent_id,customer_id:user.id,order_reference:orderReference,customer_phone_number:phone}).select("id").single(); if(error)throw new Error(error.message);
    try {
      const token=await fetchClickPesaToken(config); const preview=await previewUssdPushRequest(config,token,payload);
      if(!(preview.activeMethods??[]).some(m=>(m.status??"").toUpperCase()==="AVAILABLE"))throw new ClickPesaRequestError("No mobile-money method is available for this phone.",400,preview);
      const initiated=await initiateUssdPushRequest(config,token,payload); const status=mapClickPesaStatus(initiated.status);
      await db.from("listing_chat_payments").update({payment_status:status,provider_payment_id:initiated.id??null,provider_channel:preview.sender?.accountProvider??initiated.channel??null,provider_response:{preview,initiated}}).eq("id",payment.id);
      return json({success:true,paymentRequired:true,paymentId:payment.id,paymentStatus:status,amount:AMOUNT,currency:"TZS"});
    }catch(error){await db.from("listing_chat_payments").update({payment_status:"failed",failed_at:new Date().toISOString(),status_message:error instanceof Error?error.message:"Payment failed"}).eq("id",payment.id);throw error;}
  }catch(error){return json({error:error instanceof Error?error.message:"Could not start chat payment."},error instanceof ClickPesaRequestError?error.status:500);}
});
