import { createClient } from "npm:@supabase/supabase-js@2";

const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{"Content-Type":"application/json"}});
const b64url=(value:string|Uint8Array)=>{const bytes=typeof value==="string"?new TextEncoder().encode(value):value;let binary="";for(const b of bytes)binary+=String.fromCharCode(b);return btoa(binary).replaceAll("+","-").replaceAll("/","_").replace(/=+$/g,"");};
async function accessToken(){
 const raw=Deno.env.get("FIREBASE_SERVICE_ACCOUNT_B64")??"";if(!raw)throw new Error("Firebase service account is not configured");
 const account=JSON.parse(atob(raw));const now=Math.floor(Date.now()/1000);const header=b64url(JSON.stringify({alg:"RS256",typ:"JWT"}));const claims=b64url(JSON.stringify({iss:account.client_email,scope:"https://www.googleapis.com/auth/firebase.messaging",aud:"https://oauth2.googleapis.com/token",iat:now,exp:now+3600}));
 const pem=String(account.private_key).replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g,"");const der=Uint8Array.from(atob(pem),c=>c.charCodeAt(0));const key=await crypto.subtle.importKey("pkcs8",der,{name:"RSASSA-PKCS1-v1_5",hash:"SHA-256"},false,["sign"]);const signature=new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5",key,new TextEncoder().encode(`${header}.${claims}`)));const assertion=`${header}.${claims}.${b64url(signature)}`;
 const response=await fetch("https://oauth2.googleapis.com/token",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},body:new URLSearchParams({grant_type:"urn:ietf:params:oauth:grant-type:jwt-bearer",assertion})});const payload=await response.json();if(!response.ok||!payload.access_token)throw new Error(payload.error_description??"Could not authorize Firebase messaging");return payload.access_token as string;
}
Deno.serve(async request=>{
 if(request.method!=="POST")return json({error:"Method not allowed"},405);
 const db=createClient(Deno.env.get("SUPABASE_URL")??"",Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")??"");
 try{
  const{data:jobs,error}=await db.from("notification_delivery_outbox").select("id,notification_id,user_id,attempt_count").in("status",["pending","failed"]).lte("next_attempt_at",new Date().toISOString()).order("created_at").limit(30);if(error)throw error;if(!jobs?.length)return json({success:true,processed:0});
  const token=await accessToken();let sent=0;let failed=0;
  for(const job of jobs){
   const{data:claimed}=await db.from("notification_delivery_outbox").update({status:"processing",attempt_count:job.attempt_count+1,updated_at:new Date().toISOString()}).eq("id",job.id).in("status",["pending","failed"]).select("id").maybeSingle();if(!claimed)continue;
   try{
    const[{data:n},{data:devices},{data:prefs}]=await Promise.all([db.from("notifications").select("title,body,payload,type").eq("id",job.notification_id).single(),db.from("device_tokens").select("id,device_token,platform,app_surface").eq("user_id",job.user_id).eq("is_enabled",true),db.from("notification_preferences").select("chat_enabled,requests_enabled,payments_enabled,reminders_enabled,promotions_enabled").eq("user_id",job.user_id).maybeSingle()]);if(!n||!devices?.length){await db.from("notification_delivery_outbox").update({status:"skipped",processed_at:new Date().toISOString(),last_error:"No active device"}).eq("id",job.id);continue;}
    const event=String((n.payload as Record<string,unknown>??{}).eventType??n.type??"");const allowed=event.includes("chat")?prefs?.chat_enabled!==false:event.includes("payment")?prefs?.payments_enabled!==false:event.includes("reminder")||event.includes("viewing")?prefs?.reminders_enabled!==false:event.includes("promotion")||event.includes("price")?prefs?.promotions_enabled!==false:prefs?.requests_enabled!==false;if(!allowed){await db.from("notification_delivery_outbox").update({status:"skipped",processed_at:new Date().toISOString(),last_error:"Disabled by user preference"}).eq("id",job.id);continue;}
    const ids:string[]=[];for(const device of devices){const data:Record<string,string>={};for(const[k,v]of Object.entries((n.payload??{})as Record<string,unknown>))data[k]=typeof v==="string"?v:JSON.stringify(v);data.notificationId=job.notification_id;
      const response=await fetch(`https://fcm.googleapis.com/v1/projects/${Deno.env.get("FIREBASE_PROJECT_ID")??"kodimali"}/messages:send`,{method:"POST",headers:{Authorization:`Bearer ${token}`,"Content-Type":"application/json"},body:JSON.stringify({message:{token:device.device_token,notification:{title:n.title,body:n.body},data,android:{priority:"high",notification:{channel_id:data.eventType?.includes("chat")?"kodimali_chat":"kodimali_updates",sound:"default"}},apns:{payload:{aps:{sound:"default","content-available":1}}}}})});const payload=await response.json();if(response.ok&&payload.name)ids.push(payload.name);else if(response.status===404||response.status===400){await db.from("device_tokens").update({is_enabled:false}).eq("id",device.id);}}
    await db.from("notification_delivery_outbox").update({status:ids.length?"sent":"failed",firebase_message_ids:ids,processed_at:ids.length?new Date().toISOString():null,last_error:ids.length?null:"Firebase rejected every device",next_attempt_at:new Date(Date.now()+15000).toISOString()}).eq("id",job.id);if(ids.length)sent++;else failed++;
   }catch(error){failed++;await db.from("notification_delivery_outbox").update({status:"failed",last_error:error instanceof Error?error.message:String(error),next_attempt_at:new Date(Date.now()+15000).toISOString()}).eq("id",job.id);}
  }
  return json({success:true,processed:sent+failed,sent,failed});
 }catch(error){return json({error:error instanceof Error?error.message:String(error)},500);}
});
