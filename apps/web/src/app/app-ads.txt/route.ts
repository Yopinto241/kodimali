export const dynamic = "force-dynamic";

export function GET() {
  const publisherId = process.env.ADMOB_PUBLISHER_ID?.trim();
  if (!publisherId || !/^pub-\d+$/.test(publisherId)) {
    return new Response("AdMob publisher ID is not configured.\n", { status: 404, headers: { "Content-Type": "text/plain; charset=utf-8" } });
  }
  return new Response(`google.com, ${publisherId}, DIRECT, f08c47fec0942fa0\n`, { headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "public, max-age=3600" } });
}
