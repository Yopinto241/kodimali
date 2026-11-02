import { fetchPromotions, supabaseFetch } from "@/lib/supabase-public";
export async function GET(request: Request) {
  const url=new URL(request.url), locationId=url.searchParams.get("locationId");
  const geo: Record<string,string>={};
  if(locationId && !/^[0-9a-f-]{36}$/i.test(locationId)) return Response.json([], {status:400});
  try {
    let parent=locationId;
    for(let level=0;parent && level<5;level++){
      const rows=await supabaseFetch(`/rest/v1/locations?select=id,parent_id,location_type&id=eq.${encodeURIComponent(parent)}&is_active=eq.true`,undefined,{revalidate:3600,tags:["public-locations"]});
      const row=rows[0];if(!row)break;
      if(["region","district","ward","area"].includes(row.location_type))geo[`${row.location_type}Id`]=row.id;
      parent=row.parent_id;
    }
    return Response.json(await fetchPromotions({surface:"website",placement:"category_page",categorySlug:"events",...geo}));
  } catch { return Response.json([]); }
}
