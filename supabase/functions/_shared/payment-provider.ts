import {
  checkSonicPesaOrder,
  createSonicPesaOrder,
  SonicPesaRequestError,
  type SonicPesaStatus,
} from "./sonicpesa.ts";

export type CollectionProvider = "sonicpesa";
export type CollectionStatus = SonicPesaStatus;

export type CollectionOrder = {
  provider: CollectionProvider;
  orderId: string;
  status: CollectionStatus;
  transactionId?: string | null;
  channel?: string | null;
  payload: unknown;
};

export class PaymentProviderError extends Error {
  constructor(message: string, public status = 500, public payload?: unknown) {
    super(message);
    this.name = "PaymentProviderError";
  }
}

export function selectedCollectionProvider(): CollectionProvider {
  const configured =
    (Deno.env.get("KODIMALI_COLLECTION_PROVIDER") ?? "sonicpesa")
      .trim().toLowerCase();
  if (configured !== "sonicpesa") {
    throw new PaymentProviderError(
      `The configured collection provider '${configured}' has no approved KODIMALI adapter.`,
      503,
    );
  }
  return configured;
}

function translateError(error: unknown): never {
  if (error instanceof SonicPesaRequestError) {
    throw new PaymentProviderError(error.message, error.status, error.payload);
  }
  throw error;
}

export async function createCollectionOrder(input: {
  phone: string;
  amount: number;
  email?: string;
  name?: string;
}): Promise<CollectionOrder> {
  const provider = selectedCollectionProvider();
  try {
    const result = await createSonicPesaOrder(input);
    return { provider, ...result };
  } catch (error) {
    translateError(error);
  }
}

export async function checkCollectionOrder(
  providerValue: unknown,
  orderId: string,
): Promise<CollectionOrder> {
  const provider = String(providerValue ?? "").trim().toLowerCase();
  if (provider !== "sonicpesa") {
    throw new PaymentProviderError(
      provider
        ? `No approved status adapter exists for '${provider}'.`
        : "The historical payment order does not identify its provider.",
      409,
    );
  }
  try {
    const result = await checkSonicPesaOrder(orderId);
    return { provider, ...result };
  } catch (error) {
    translateError(error);
  }
}
