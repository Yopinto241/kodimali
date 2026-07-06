const supabaseUrl =
  process.env.SUPABASE_URL ?? "https://tlhoajedyaeaaqtrjqqh.supabase.co";
const supabasePublishableKey =
  process.env.SUPABASE_PUBLISHABLE_KEY ??
  "sb_publishable_3Txem_vMHZbvLswFzjR6ng_OGXbur1K";

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const response = await fetch(
      `${supabaseUrl}/functions/v1/create-listing-contact-payment`,
      {
        method: "POST",
        headers: {
          apikey: supabasePublishableKey,
          Authorization: `Bearer ${supabasePublishableKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      },
    );

    const payload = await response.json();
    if (!response.ok) {
      return Response.json(
        { error: payload.error ?? "Could not start the payment." },
        { status: response.status },
      );
    }

    return Response.json(payload);
  } catch (error) {
    return Response.json(
      {
        error:
          error instanceof Error && error.message.trim().length > 0
            ? error.message
            : "Could not start the payment.",
      },
      { status: 500 },
    );
  }
}
