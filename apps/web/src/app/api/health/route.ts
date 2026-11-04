import { safeUserMessage } from "@/lib/user-message";
import { checkPublicBackendHealth } from "@/lib/supabase-public";

export const dynamic = "force-dynamic";

export async function GET() {
  const checkedAt = new Date().toISOString();
  try {
    const backend = await checkPublicBackendHealth();
    return Response.json(
      { status: "ok", checkedAt, backend },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch (error) {
    return Response.json(
      {
        status: "degraded",
        checkedAt,
        error: safeUserMessage(error),
      },
      { status: 503, headers: { "Cache-Control": "no-store" } },
    );
  }
}
