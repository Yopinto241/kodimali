import { appleAssociations } from "@/lib/mobile-associations";
export const dynamic="force-dynamic";
export async function GET() {
  try {
    const entries=appleAssociations(process.env);
    if (!entries) return Response.json({error:"iOS release configuration pending"},{status:503,headers:{"Cache-Control":"no-store"}});
    return Response.json(entries,{headers:{"Cache-Control":"public, max-age=300"}});
  } catch { return Response.json({error:"Release association configuration unavailable"},{status:503,headers:{"Cache-Control":"no-store"}}); }
}
