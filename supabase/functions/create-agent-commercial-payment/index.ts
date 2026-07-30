import { createClient } from "npm:@supabase/supabase-js@2";
import { ClickPesaRequestError, createChecksum, fetchClickPesaToken, formatAmount, initiateUssdPushRequest, json, mapClickPesaStatus, normalizePhoneNumber, previewUssdPushRequest, readClickPesaConfig } from "../_shared/clickpesa.ts";
const reference=()=>`BZ${crypto.randomUUID().replaceAll("-","").slice(0,18).toUpperCase()}`;
Deno.serve(async(request)=>{
 if(request.method!=="POST")return json({error:"Method not allowed"},405);
 const db=createClient(Deno.env.get("SUPABASE_URL")??"",Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")??"");
 try{
  const jwt=(request.headers.get("Authorization")??"").replace(/^Bearer\s+/i,""); const {data:{user}}=await db.auth.getUser(jwt); if(!user)return json({error:"Sign in as an agent."},401);
  const {data:agent}=await db.from("agents").select("id").eq("profile_id",user.id).single(); if(!agent)return json({error:"Agent account not found."},403);
  const body=await request.json(); const type=String(body?.product_type??""); const phone=normalizePhoneNumber(String(body?.phone_number??""));
  let amount=0,planId:null|string=null,boostId:null|string=null;
  if(type==="subscription"){
   planId=String(body?.plan_id??""); const {data:plan}=await db.from("agent_subscription_plans").select("monthly_price_tzs,is_active").eq("id",planId).single(); if(!plan?.is_active||Number(plan.monthly_price_tzs)<=0)return json({error:"Choose a paid active plan."},400); amount=Number(plan.monthly_price_tzs);
  }else if(type==="listing_boost"){
   boostId=String(body?.listing_boost_id??""); const {data:boost}=await db.from("listing_boosts").select("amount_tzs,agent_id,status").eq("id",boostId).single(); if(!boost||boost.agent_id!==agent.id||boost.status!=="pending")return json({error:"Boost request is unavailable."},400); amount=Number(boost.amount_tzs);
  }else return json({error:"Unsupported product."},400);
  const {data:paymentEnabled,error:settingError}=await db.rpc("commercial_payment_enabled",{p_product_type:type});if(settingError)throw new Error(settingError.message);
  if(paymentEnabled===false){
   if(type==="subscription"){
    await db.from("agent_subscriptions").update({status:"expired",updated_at:new Date().toISOString()}).eq("agent_id",agent.id).eq("status","active");
    const {error}=await db.from("agent_subscriptions").insert({agent_id:agent.id,plan_id:planId,status:"active",starts_at:new Date().toISOString(),expires_at:new Date(Date.now()+30*86400000).toISOString()});if(error)throw new Error(error.message);
   }else{
    const {data:boost}=await db.from("listing_boosts").select("duration_days").eq("id",boostId).single();const starts=new Date();const ends=new Date(starts.getTime()+Number(boost?.duration_days??7)*86400000);const {error}=await db.from("listing_boosts").update({status:"active",starts_at:starts.toISOString(),ends_at:ends.toISOString(),updated_at:starts.toISOString()}).eq("id",boostId).eq("agent_id",agent.id);if(error)throw new Error(error.message);
   }
   return json({success:true,paymentRequired:false,paymentStatus:"free",amount:0,currency:"TZS"});
  }
  if(phone.length<12)return json({error:"Enter a valid mobile-money number."},400);
  const orderReference=reference(); const {data:payment,error}=await db.from("agent_commercial_payments").insert({agent_id:agent.id,product_type:type,plan_id:planId,listing_boost_id:boostId,order_reference:orderReference,requested_amount:amount,customer_phone_number:phone}).select("id").single(); if(error)throw new Error(error.message);
  const config=readClickPesaConfig({clientIdEnv:"CLICKPESA_COLLECTION_CLIENT_ID",apiKeyEnv:"CLICKPESA_COLLECTION_API_KEY",checksumKeyEnv:"CLICKPESA_COLLECTION_CHECKSUM_KEY"}); const payload:Record<string,unknown>={amount:formatAmount(amount),currency:"TZS",orderReference,phoneNumber:phone}; if(config.checksumKey)payload.checksum=createChecksum(config.checksumKey,payload);
  try{const token=await fetchClickPesaToken(config);const preview=await previewUssdPushRequest(config,token,payload);if(!(preview.activeMethods??[]).some(m=>(m.status??"").toUpperCase()==="AVAILABLE"))throw new ClickPesaRequestError("No mobile-money method is available for this phone.",400,preview);const initiated=await initiateUssdPushRequest(config,token,payload);const status=mapClickPesaStatus(initiated.status);await db.from("agent_commercial_payments").update({payment_status:status,provider_payment_id:initiated.id??null,provider_channel:preview.sender?.accountProvider??initiated.channel??null,provider_response:{preview,initiated}}).eq("id",payment.id);return json({success:true,paymentId:payment.id,paymentStatus:status,amount,currency:"TZS"});}catch(error){await db.from("agent_commercial_payments").update({payment_status:"failed",failed_at:new Date().toISOString(),status_message:error instanceof Error?error.message:"Payment failed"}).eq("id",payment.id);throw error;}
 }catch(error){return json({error:error instanceof Error?error.message:"Could not start payment."},error instanceof ClickPesaRequestError?error.status:500);}
});
