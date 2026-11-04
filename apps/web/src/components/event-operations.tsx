"use client";
import Link from "next/link";
import { useCallback, useEffect, useState, type FormEvent } from "react";
import { getBrowserSupabase } from "@/lib/supabase-browser";
import { safeUserMessage } from "@/lib/user-message";
import { useLanguage } from "@/components/language-provider";
import { EventLocationFields } from "@/components/event-location-fields";
import { UiText } from "@/components/ui-text";

import type { SupabaseClient } from "@supabase/supabase-js";
type Row=Record<string,unknown>;
type EventDatabase={public:{Tables:Record<string,{Row:Row;Insert:Row;Update:Row;Relationships:[]}>;Views:Record<string,never>;Functions:Record<string,{Args:Row;Returns:unknown}>;Enums:Record<string,never>;CompositeTypes:Record<string,never>}};
type Result={error: {message:string}|null};
const list=(value:unknown):Row[]=>Array.isArray(value)?value as Row[]:[];
import { providerEventViews, coordinatorEventViews } from "@/lib/event-operation-routes";
export function EventOperations({mode,view}:{mode:"provider"|"coordinator";view:string}) {
  const db=getBrowserSupabase() as unknown as SupabaseClient<EventDatabase>;
  const {language}=useLanguage();
  const [loading,setLoading]=useState(true),[busy,setBusy]=useState(false);
  const [allowed,setAllowed]=useState(false),[signedIn,setSignedIn]=useState(false);
  const [permissions,setPermissions]=useState<string[]>([]);
  const [data,setData]=useState<Record<string,Row[]>>({});
  const [owner,setOwner]=useState<string|null>(null),[profile,setProfile]=useState<Row|null>(null);
  const [location,setLocation]=useState("");
  const [message,setMessage]=useState("");
  const can=(permission:string)=>permissions.includes("*")||permissions.includes(permission);
  const load=useCallback(async()=>{
    setLoading(true);
    try {
      const auth=await db.auth.getUser();
      setSignedIn(!!auth.data.user);
      if (!auth.data.user) {setAllowed(false);return;}
      const roles=await db.from("user_roles").select("role").eq("profile_id",auth.data.user.id);
      const access=await db.rpc("get_my_admin_permissions");
      if (roles.error||access.error) throw roles.error??access.error;
      const grants=Array.isArray(access.data)?access.data as string[]:[];
      const authorized=mode==="coordinator" ? grants.includes("*")||grants.includes("events.manage") : (roles.data??[]).some(row=>["agent","owner"].includes(String(row.role)))||grants.includes("*");
      setPermissions(grants);setAllowed(authorized);
      if (!authorized) {setData({});return;}
      const read=async(table:string,select="*")=>{
        const result=await db.from(table).select(select).order("created_at",{ascending:false}).limit(100);
        if (result.error) throw result.error;
        return list(result.data);
      };
      if (mode==="coordinator") {
        const [plans,equipment,profiles,offerings,escalations,cancellations,tasks,disputes]=await Promise.all([
          read("event_plans","*,event_plan_items(*),event_quote_revisions(id,revision,status,total_tzs),event_agreements(id,status,version)"),
          read("event_equipment_items"),read("event_service_profiles"),read("event_service_offerings"),
          read("event_emergency_escalations"),read("event_cancellations"),read("event_tasks"),read("event_disputes"),
        ]);
        const reviews=grants.includes("*")||grants.includes("payments.manage") ? await read("financial_reconciliation_cases","*,payment_intents(resource_type,resource_id)") : [];
        setData({plans,equipment,profiles,offerings,escalations,cancellations,reviews,tasks,disputes});
      } else {
        const [ownerResult,provider]=await Promise.all([db.rpc("current_owner_id"),db.from("event_service_profiles").select("*").eq("profile_id",auth.data.user.id).maybeSingle()]);
        if (ownerResult.error||provider.error) throw ownerResult.error??provider.error;
        const ownerId=typeof ownerResult.data==="string"?ownerResult.data:null;
        setOwner(ownerId);setProfile(provider.data);
        const equipment=ownerId?await db.from("event_equipment_items").select("*").eq("owner_id",ownerId).order("created_at").limit(100):{data:[],error:null};
        const offerings=provider.data?await db.from("event_service_offerings").select("*").eq("provider_id",String((provider.data as Row).id)).order("created_at").limit(100):{data:[],error:null};
        const categories=await db.from("event_equipment_categories").select("id,name_en,name_sw");
        const requests=await db.from("event_plan_items").select("*,event_plans(reference,event_period,status),event_individual_bookings(id,status)").order("created_at",{ascending:false}).limit(100);
        const failure=[equipment,offerings,categories,requests].find(result=>result.error);
        if (failure?.error) throw failure.error;
        const tasks=await db.from("event_tasks").select("*").eq("assigned_profile_id",auth.data.user.id).order("due_at").limit(100);
        if (tasks.error) throw tasks.error;
        setData({tasks:list(tasks.data),equipment:list(equipment.data),offerings:list(offerings.data),categories:list(categories.data),requests:list(requests.data)});
      }
    } catch(error) {setMessage(safeUserMessage(error,language));}
    finally {setLoading(false);}
  },[db,mode,language]);
  useEffect(()=>{const timer=setTimeout(()=>{void load();},0);const listener=db.auth.onAuthStateChange(()=>{setAllowed(false);setData({});setTimeout(()=>{void load();},0);});return()=>{clearTimeout(timer);listener.data.subscription.unsubscribe();};},[db,load]);
  async function act(operation:()=>PromiseLike<Result>) {
    if (busy) return;
    setBusy(true);setMessage("");
    try {const result=await operation();if(result.error)throw result.error;await load();setMessage(language==="sw"?"Mabadiliko yamehifadhiwa.":"Changes saved.");}
    catch(error){setMessage(safeUserMessage(error,language));}
    finally{setBusy(false);}
  }
  const rpc=(name:string,params:Row)=>act(()=>db.rpc(name,params));
  const root=`/manage/events-${mode}`;
  const views=mode==="provider"?providerEventViews:coordinatorEventViews;
  if (loading) return <main className="manage-content" aria-busy="true"><div className="navigation-progress" role="status"><UiText text="Loading your workspace..." /></div></main>;
  if (!signedIn) return <main className="manage-content"><Link className="btn btn-success" href={`/login?next=${root}`}><UiText text="Sign in" /></Link></main>;
  if (!allowed) return <main className="manage-content"><p role="alert"><UiText text="Access unavailable" /></p><Link href="/manage"><UiText text="Back" /></Link></main>;
  return <main className="manage-content mx-auto max-w-6xl p-4 sm:p-8">
    <Link className="btn btn-outline mb-4" href="/manage"><UiText text="Back to workspace" /></Link>
    <h1 className="text-3xl font-semibold"><UiText text={mode==="provider"?"Events provider workspace":"Events coordinator workspace"} /></h1>
    <nav className="my-5 flex flex-wrap gap-3" aria-label="Events operations">{views.map(item=><Link className="btn btn-outline" aria-current={view===item?"page":undefined} key={item} href={`${root}/${item}`}><UiText text={item[0].toUpperCase()+item.slice(1)} /></Link>)}</nav>
    {message&&<p role="status" className="soft-panel my-4 p-4">{message}</p>}
    <button className="btn btn-outline mb-4" onClick={()=>void load()} disabled={busy}><UiText text="Refresh" /></button>
    {mode==="provider"&&view==="equipment"&&<>
      {owner?<OperationForm title="Add equipment" busy={busy} fields={[{name:"name",label:"Name"},{name:"category_id",label:"Category",options:(data.categories??[]).map(row=>[String(row.id),String(language==="sw"?row.name_sw:row.name_en)])},{name:"total_quantity",label:"Quantity",type:"number",min:1},{name:"price_amount_tzs",label:"Price (TZS)",type:"number",min:0}]} extra={<EventLocationFields value={location} onChange={setLocation} required/>} submit={values=>act(()=>db.from("event_equipment_items").insert({...values,owner_id:owner,total_quantity:Number(values.total_quantity),price_amount_tzs:Number(values.price_amount_tzs),location_id:location,condition:"good",price_unit:"item_event"}))}/>:<p><UiText text="Verified owner access is required to add equipment." /></p>}
      {(data.equipment??[]).map(row=><article className="surface-card my-4 p-5" key={String(row.id)}><h2 className="font-semibold">{String(row.name)}</h2><p>{String(row.verification_status)} · {String(row.publication_status)}</p>
        <OperationForm title="Edit equipment" busy={busy} fields={[{name:"name",label:"Name",value:row.name},{name:"total_quantity",label:"Quantity",type:"number",min:1,value:row.total_quantity},{name:"price_amount_tzs",label:"Price (TZS)",type:"number",min:0,value:row.price_amount_tzs}]} submit={values=>act(()=>db.from("event_equipment_items").update({...values,total_quantity:Number(values.total_quantity),price_amount_tzs:Number(values.price_amount_tzs)}).eq("id",String(row.id)))}/>
        <button className="btn btn-outline" disabled={busy} onClick={()=>void act(()=>db.from("event_equipment_items").update({is_active:!row.is_active}).eq("id",String(row.id)))}><UiText text={row.is_active?"Pause":"Activate"}/></button>
      </article>)}
    </>}
    {mode==="provider"&&view==="services"&&<>
      {!profile?<OperationForm title="Register professional profile" busy={busy} fields={[{name:"display_name",label:"Name"},{name:"provider_kind",label:"Profession",options:["planner","decorator","photographer","dj","caterer","mc_host"].map(value=>[value,value])},{name:"biography",label:"Description"}]} submit={values=>act(async()=>{const auth=await db.auth.getUser();return db.from("event_service_profiles").insert({...values,profile_id:auth.data.user?.id});})}/>:<>
        <p>{String(profile.display_name)} · {String(profile.verification_status)}</p>
        <OperationForm title="Add service" busy={busy} fields={[{name:"title",label:"Title"},{name:"description",label:"Description"},{name:"price_amount_tzs",label:"Price (TZS)",type:"number",min:0},{name:"duration_minutes",label:"Duration (minutes)",type:"number",min:1}]} submit={values=>act(()=>db.from("event_service_offerings").insert({...values,provider_id:profile.id,pricing_mode:"fixed",price_amount_tzs:Number(values.price_amount_tzs),duration_minutes:Number(values.duration_minutes)}))}/>
        <OperationForm title="Service area" busy={busy} fields={[]} extra={<EventLocationFields value={location} onChange={setLocation} required/>} submit={()=>act(()=>db.from("event_service_areas").insert({profile_id:profile.id,location_id:location}))}/>
      </>}
      {(data.offerings??[]).map(row=><article className="surface-card my-4 p-5" key={String(row.id)}><h2>{String(row.title)}</h2><OperationForm title="Edit service" busy={busy} fields={[{name:"title",label:"Title",value:row.title},{name:"price_amount_tzs",label:"Price (TZS)",type:"number",min:0,value:row.price_amount_tzs}]} submit={values=>act(()=>db.from("event_service_offerings").update({...values,price_amount_tzs:Number(values.price_amount_tzs)}).eq("id",String(row.id)))}/></article>)}
    </>}
    {mode==="provider"&&view==="requests"&&(data.requests??[]).map(row=>{
      const individual=list(row.event_individual_bookings)[0];
      return <article className="surface-card my-4 p-5" key={String(row.id)}><h2>{String(row.plan_id)}</h2><p>{String(row.item_kind)} · {String(row.requested_quantity)} · {String(row.status)}</p>
        <button className="btn btn-success" disabled={busy||!["requested","quoted","provider_confirmed"].includes(String(row.status))} onClick={()=>void (individual?rpc("respond_individual_event_booking",{p_booking_id:individual.id,p_approve:true,p_response:null}):rpc(row.item_kind==="equipment"?"confirm_event_equipment_item":"confirm_event_service_item",{p_plan_item_id:row.id,p_hold_minutes:1440,...(row.item_kind==="equipment"?{}:{p_travel_buffer_minutes:60})}))}><UiText text="Confirm request"/></button>
        {individual&&<OperationForm title="Send quotation" busy={busy} fields={[{name:"amount",label:"Price (TZS)",type:"number",min:0},{name:"terms",label:"Terms"}]} submit={values=>rpc("send_individual_booking_quote",{p_booking_id:individual.id,p_amount_tzs:Number(values.amount),p_terms:values.terms,p_expires_at:new Date(Date.now()+3*86400000).toISOString()})}/>}
        <OperationForm title="Cancel or report unavailability" busy={busy} fields={[{name:"reason",label:"Reason"}]} submit={values=>rpc("provider_cancel_event_item",{p_plan_item_id:row.id,p_reason:values.reason})}/>
      </article>;
    })}
    {mode==="coordinator"&&view==="plans"&&(data.plans??[]).map(plan=><article className="surface-card my-4 p-5" key={String(plan.id)}><h2 className="font-semibold">{String(plan.reference)} · {String(plan.title)}</h2><p>{String(plan.event_period)} · {String(plan.status)}</p>
      <p>{list(plan.event_plan_items).map(item=>`${String(item.item_kind)}: ${String(item.status)}`).join("; ")}</p>
      {can("events.quotes")&&<OperationForm title="Send itemized quotation" busy={busy} fields={[...list(plan.event_plan_items).flatMap((item,index)=>[
        {name:`description_${item.id}`,label:language==="sw"?`Kipengele ${index+1}`:`Item ${index+1}`,value:item.item_kind},
        {name:`quantity_${item.id}`,label:"Quantity",type:"number",min:1,value:item.requested_quantity||1},
        {name:`price_${item.id}`,label:"Unit price (TZS)",type:"number",min:0},
      ]),{name:"additional",label:"Additional costs (TZS)",type:"number",min:0,value:0}]} submit={values=>{
        const items=list(plan.event_plan_items).map(item=>({plan_item_id:item.id,description:values[`description_${item.id}`],quantity:Number(values[`quantity_${item.id}`]),unit_price_tzs:Number(values[`price_${item.id}`])}));
        return rpc("create_event_quote_revision",{p_plan_id:plan.id,p_expires_at:new Date(Date.now()+3*86400000).toISOString(),p_items:items,p_additional_costs_tzs:Number(values.additional)});
      }}/>}
      <OperationForm title="Send agreement" busy={busy} fields={[{name:"terms",label:"Terms",type:"textarea"}]} submit={values=>rpc("send_event_agreement",{p_plan_id:plan.id,p_terms:values.terms})}/>
    </article>)}
    {mode==="coordinator"&&view==="approvals"&&["equipment","profiles","offerings"].flatMap(kind=>(data[kind]??[]).map(row=><article className="surface-card my-4 p-5" key={`${kind}-${row.id}`}><h2>{String(row.name??row.display_name??row.title)}</h2><p>{String(row.verification_status??row.publication_status)}</p>
      <button className="btn btn-success" disabled={busy} onClick={()=>void act(()=>db.from(kind==="equipment"?"event_equipment_items":kind==="profiles"?"event_service_profiles":"event_service_offerings").update(kind==="profiles"?{verification_status:"verified"}:kind==="equipment"?{verification_status:"verified",publication_status:"published"}:{publication_status:"published"}).eq("id",String(row.id)))}><UiText text="Approve and publish"/></button>
      <button className="btn btn-outline" disabled={busy} onClick={()=>void act(()=>db.from(kind==="equipment"?"event_equipment_items":kind==="profiles"?"event_service_profiles":"event_service_offerings").update({is_active:false}).eq("id",String(row.id)))}><UiText text="Pause"/></button>
    </article>))}
    {mode==="coordinator"&&view==="escalations"&&(data.escalations??[]).map(row=><article className="surface-card my-4 p-5" key={String(row.id)}><h2>{String(row.reason)}</h2><p>{String(row.status)}</p>
      {can("events.escalations")&&<><OperationForm title="Propose replacement" busy={busy} fields={[{name:"replacement",label:"Verified replacement",options:[...(data.equipment??[]).filter(item=>item.verification_status==="verified"&&item.publication_status==="published").map(item=>[String(item.id),String(item.name)]),...(data.offerings??[]).filter(item=>item.publication_status==="published").map(item=>[String(item.id),String(item.title)])]},{name:"reason",label:"Reason"},{name:"difference",label:"Price change (TZS)",type:"number",value:0}]} submit={values=>rpc("propose_event_replacement",{p_item_id:row.plan_item_id,p_replacement_id:values.replacement,p_reason:values.reason,p_price_change_tzs:Number(values.difference)})}/>
      <OperationForm title="Resolve escalation" busy={busy} fields={[{name:"resolution",label:"Resolution"}]} submit={values=>rpc("resolve_event_escalation",{p_escalation_id:row.id,p_resolution:values.resolution})}/></>}
    </article>)}
    {view==="tasks"&&(data.tasks??[]).map(row=><article className="surface-card my-4 p-5" key={String(row.id)}><h2>{String(row.title)}</h2><p>{String(row.details??"")}</p><p>{String(row.due_at??"")} ? {String(row.status)}</p>{!["completed","cancelled"].includes(String(row.status))&&<OperationForm title="Update fulfillment task" busy={busy} fields={[{name:"status",label:"Status",options:[["in_progress","In progress"],["blocked","Blocked"],["completed","Completed"]]}]} submit={values=>rpc("update_event_fulfillment_task",{p_task_id:row.id,p_status:values.status})}/>}</article>)}
    {mode==="coordinator"&&view==="support"&&(data.disputes??[]).map(row=><article className="surface-card my-4 p-5" key={String(row.id)}><h2>{String(row.reason)}</h2><p>{String(row.details??"")}</p><p>{String(row.status)} ? {String(row.resolution??"")}</p><OperationForm title="Review dispute" busy={busy} fields={[{name:"status",label:"Status",options:[["investigating","Investigating"],["resolved","Resolved"],["rejected","Rejected"]]},{name:"resolution",label:"Resolution",type:"textarea"}]} submit={values=>rpc("resolve_event_dispute",{p_dispute_id:row.id,p_status:values.status,p_resolution:values.resolution})}/></article>)}
    {mode==="coordinator"&&view==="finance"&&(can("payments.manage")?<>
      {(data.reviews??[]).filter(row=>{const intent=row.payment_intents as Row|null;return intent?.resource_type==="event_plan";}).map(row=><article className="surface-card my-4 p-5" key={String(row.id)}><p>{String(row.reason)}</p><OperationForm title="Record payment review" busy={busy} fields={[{name:"decision",label:"Decision",options:[["refund_recorded","Refund recorded"],["credit_for_replacement","Retain for replacement"]]},{name:"reference",label:"Completed transaction reference"}]} submit={values=>rpc("resolve_event_payment_review",{p_case_id:row.id,p_decision:values.decision,p_reference:values.reference})}/></article>)}
      {(data.cancellations??[]).map(row=><article className="surface-card my-4 p-5" key={String(row.id)}><p>{String(row.reason)}</p><OperationForm title="Record completed cancellation settlement" busy={busy} fields={[{name:"reference",label:"Completed transaction reference"},{name:"amount",label:"Refund amount (TZS)",type:"number",min:0}]} submit={values=>rpc("record_event_cancellation_settlement",{p_cancellation_id:row.id,p_transaction_reference:values.reference,p_refund_amount_tzs:Number(values.amount)})}/></article>)}
    </>:<p role="alert"><UiText text="Finance permission required"/></p>)}
  </main>;
}

type Field={name:string;label:string;type?:string;min?:number;value?:unknown;options?:string[][]};
function OperationForm({title,fields,busy,submit,extra}:{title:string;fields:Field[];busy:boolean;submit:(values:Row)=>unknown;extra?:React.ReactNode}) {
  function save(event:FormEvent<HTMLFormElement>) {event.preventDefault();const values=Object.fromEntries(new FormData(event.currentTarget));void submit(values);}
  return <details className="soft-panel my-3 p-4"><summary className="cursor-pointer font-semibold"><UiText text={title}/></summary><form className="mt-4 grid gap-3 sm:grid-cols-2" onSubmit={save}><fieldset disabled={busy} className="contents">{fields.map(field=><label className="field-label min-w-0" key={field.name}><UiText text={field.label}/>{field.options?<select required className="field-input mt-1" name={field.name} defaultValue={String(field.value??field.options[0]?.[0]??"")}>{field.options.map(([value,label])=><option key={value} value={value}><UiText text={label}/></option>)}</select>:field.type==="textarea"?<textarea required className="field-input mt-1 min-h-28" name={field.name} defaultValue={String(field.value??"")}/>:<input required className="field-input mt-1" name={field.name} type={field.type??"text"} min={field.min} defaultValue={String(field.value??"")} maxLength={field.type==="number"?undefined:4000}/>}</label>)}{extra}<button className="btn btn-success mt-2" disabled={busy}><UiText text={busy?"Saving...":"Save"}/></button></fieldset></form></details>;
}
