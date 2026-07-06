import { checkListingAvailability } from "@/lib/supabase-public";

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as {
      listingId: string;
      requestedStartAt?: string;
      requestedEndAt?: string;
    };

    const payload = await checkListingAvailability(body);
    return Response.json(payload);
  } catch (error) {
    return Response.json(
      {
        error:
          error instanceof Error ? error.message : "Availability check failed",
      },
      { status: 400 },
    );
  }
}
