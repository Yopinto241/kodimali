import { submitGuestRequest } from "@/lib/supabase-public";

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as {
      listing_id: string;
      customer_name: string;
      customer_email?: string;
      customer_phone_number?: string;
      requested_start_at?: string;
      requested_end_at?: string;
      guest_count?: number;
      request_message?: string;
      requested_service_codes?: string[];
    };

    const payload = await submitGuestRequest(body);
    return Response.json(payload);
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Request failed" },
      { status: 400 },
    );
  }
}
