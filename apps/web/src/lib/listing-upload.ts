import { registrationFetch } from "@/lib/supabase-browser";

/** Uses the user's session and existing storage policies, with a bounded wait. */
export async function uploadListingPhoto(path: string, blob: Blob, accessToken: string) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "https://tlhoajedyaeaaqtrjqqh.supabase.co";
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? "sb_publishable_3Txem_vMHZbvLswFzjR6ng_OGXbur1K";
  const response = await registrationFetch(`${url}/storage/v1/object/listing-media/${path.split("/").map(encodeURIComponent).join("/")}`, {
    method: "POST", headers: { Authorization: `Bearer ${accessToken}`, apikey: key, "Content-Type": "image/jpeg", "x-upsert": "true" }, body: blob,
  }, 60000);
  if (!response.ok) throw new Error("Image upload could not be completed");
}
