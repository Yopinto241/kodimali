import { fetchLocations } from "@/lib/supabase-public";

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const locationType = searchParams.get("locationType");
  const parentId = searchParams.get("parentId") ?? undefined;

  if (!locationType) {
    return Response.json({ error: "locationType is required" }, { status: 400 });
  }

  const payload = await fetchLocations({ locationType, parentId });
  return Response.json(payload);
}
