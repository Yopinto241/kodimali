import { submitGuestRequest } from "@/lib/supabase-public";

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as {
      listing_id: string;
      customer_name: string;
      customer_phone_number: string;
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
