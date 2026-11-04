// Internal workers require a dedicated credential, never a frontend API key.
export function trustedWorker(request: Request): boolean {
  const expected = (Deno.env.get("KODIMALI_WORKER_SECRET") ?? "").trim();
  const supplied = (request.headers.get("x-kodimali-worker-secret") ?? "").trim();
  if (expected.length < 32 || supplied.length !== expected.length) return false;
  let difference = 0;
  for (let i = 0; i < expected.length; i++) difference |= expected.charCodeAt(i) ^ supplied.charCodeAt(i);
  return difference === 0;
}
