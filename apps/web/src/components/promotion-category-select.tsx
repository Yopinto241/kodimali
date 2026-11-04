"use client";
import { safeUserMessage } from "@/lib/user-message";
import { useEffect, useState } from "react";
import { getBrowserSupabase } from "@/lib/supabase-browser";
import { UiText } from "@/components/ui-text";
export function PromotionCategorySelect({id, initialIds}: {id:string; initialIds:string[]}) {
  const [categories,setCategories]=useState<{id:string;name:string}[]>([]);
  const [selected,setSelected]=useState(initialIds);
  const [message,setMessage]=useState("");
  const [busy,setBusy]=useState(false);
  useEffect(()=>{let active=true;void Promise.resolve(getBrowserSupabase().from("asset_categories").select("id,name").order("display_order")).then(({data,error})=>{if(active){if(error)setMessage(safeUserMessage(error));else setCategories(data??[]);}});return()=>{active=false;};},[]);
  return <fieldset className="mt-4 grid gap-3"><legend><UiText text="Sponsored categories" /></legend><p><UiText text="Leave all unchecked to show in every category." /></p>
    <div className="flex flex-wrap gap-3">{categories.map(category=><label key={category.id} className="flex items-center gap-2"><input type="checkbox" checked={selected.includes(category.id)} disabled={busy} onChange={event=>setSelected(current=>event.target.checked?[...current,category.id]:current.filter(id=>id!==category.id))}/><UiText text={category.name}/></label>)}</div>
    <button type="button" className="btn btn-outline" disabled={busy} onClick={async()=>{setBusy(true);try{const {error}=await getBrowserSupabase().from("platform_promotions").update({target_category_ids:selected} as never).eq("id",id);if(error)throw error;setMessage("Saved changes.");}catch(error){setMessage(safeUserMessage(error));}finally{setBusy(false);}}}><UiText text={busy?"Saving...":"Save categories"}/></button>{message&&<p role="status"><UiText text={message}/></p>}
  </fieldset>;
}
