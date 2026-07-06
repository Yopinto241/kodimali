import { createHmac, timingSafeEqual } from "node:crypto";

export class ClickPesaRequestError extends Error {
  constructor(
    message: string,
    readonly status = 500,
    readonly details: unknown = null,
  ) {
    super(message);
  }
}

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

type JsonRecord = Record<string, unknown>;

export interface ClickPesaConfig {
  apiBaseUrl: string;
  clientId: string;
  apiKey: string;
  checksumKey: string | null;
}

export interface ClickPesaConfigOptions {
  apiBaseUrlEnv?: string;
  apiKeyEnv?: string;
  checksumKeyEnv?: string;
  clientIdEnv?: string;
}

export interface ClickPesaPaymentStatus {
  id?: string;
  status?: string;
  paymentReference?: string;
  paymentPhoneNumber?: string;
  orderReference?: string;
  collectedAmount?: string | number;
  collectedCurrency?: string;
  message?: string;
  updatedAt?: string;
  createdAt?: string;
  channel?: string;
  clientId?: string;
  customer?: {
    customerName?: string;
    customerPhoneNumber?: string;
    customerEmail?: string;
  };
}

export interface ClickPesaPreviewMethod {
  name?: string;
  status?: string;
  fee?: number;
  message?: string;
}

export interface ClickPesaPreviewResponse {
  activeMethods?: ClickPesaPreviewMethod[];
  sender?: {
    accountName?: string;
    accountNumber?: string;
    accountProvider?: string;
  };
}

export interface ClickPesaInitiateResponse {
  id?: string;
  status?: string;
  channel?: string;
  orderReference?: string;
  collectedAmount?: string;
  collectedCurrency?: string;
  createdAt?: string;
  clientId?: string;
}

export function readClickPesaConfig(
  options: ClickPesaConfigOptions = {},
): ClickPesaConfig {
  const clientId = (
    Deno.env.get(options.clientIdEnv ?? "CLICKPESA_CLIENT_ID") ?? ""
  ).trim();
  const apiKey = (
    Deno.env.get(options.apiKeyEnv ?? "CLICKPESA_API_KEY") ?? ""
  ).trim();
  const checksumKey = (
    Deno.env.get(options.checksumKeyEnv ?? "CLICKPESA_CHECKSUM_KEY") ?? ""
  ).trim();
  const apiBaseUrl = (
    Deno.env.get(options.apiBaseUrlEnv ?? "CLICKPESA_API_BASE_URL") ??
      "https://api.clickpesa.com/third-parties"
  ).trim().replace(/\/+$/, "");

  if (!clientId || !apiKey) {
    throw new ClickPesaRequestError(
      "ClickPesa is not configured yet. Add CLICKPESA_CLIENT_ID and CLICKPESA_API_KEY to Supabase function secrets.",
      500,
    );
  }

  return {
    apiBaseUrl,
    clientId,
    apiKey,
    checksumKey: checksumKey.length === 0 ? null : checksumKey,
  };
}

export function normalizePhoneNumber(value: string): string {
  const digits = value.replace(/[^\d]/g, "");
  if (!digits) {
    return "";
  }
  if (digits.startsWith("255") && digits.length >= 12) {
    return digits;
  }
  if (digits.startsWith("0") && digits.length == 10) {
    return `255${digits.slice(1)}`;
  }
  if (digits.length == 9) {
    return `255${digits}`;
  }
  return digits;
}

export function formatAmount(value: number): string {
  if (Number.isInteger(value)) {
    return value.toString();
  }
  return value.toFixed(2);
}

function canonicalize(value: unknown): unknown {
  if (value === null || typeof value !== "object") {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map(canonicalize);
  }
  return Object.keys(value as JsonRecord)
    .sort()
    .reduce<JsonRecord>((acc, key) => {
      acc[key] = canonicalize((value as JsonRecord)[key]);
      return acc;
    }, {});
}

function stripChecksumFields(payload: JsonRecord): JsonRecord {
  const clone: JsonRecord = {};
  for (const [key, value] of Object.entries(payload)) {
    if (key === "checksum" || key === "checksumMethod") {
      continue;
    }
    clone[key] = value;
  }
  return clone;
}

export function createChecksum(secret: string, payload: JsonRecord): string {
  const sanitized = stripChecksumFields(payload);
  const canonicalPayload = canonicalize(sanitized);
  const payloadString = JSON.stringify(canonicalPayload);
  return createHmac("sha256", secret).update(payloadString).digest("hex");
}

export function validateChecksum(secret: string, payload: JsonRecord): boolean {
  const receivedChecksum = typeof payload.checksum === "string"
    ? payload.checksum
    : "";
  if (!receivedChecksum) {
    return false;
  }
  const computedChecksum = createChecksum(secret, payload);
  try {
    return timingSafeEqual(
      Buffer.from(computedChecksum, "utf8"),
      Buffer.from(receivedChecksum, "utf8"),
    );
  } catch (_) {
    return false;
  }
}

async function parseJsonResponse(response: Response): Promise<unknown> {
  const raw = await response.text();
  if (!raw) {
    return null;
  }
  try {
    return JSON.parse(raw);
  } catch (_) {
    return raw;
  }
}

function extractErrorMessage(payload: unknown, fallback: string): string {
  if (!payload) {
    return fallback;
  }
  if (typeof payload === "string" && payload.trim().length > 0) {
    return payload;
  }
  if (typeof payload === "object" && !Array.isArray(payload)) {
    const record = payload as JsonRecord;
    const message = record.message ?? record.error ?? record.details;
    if (typeof message === "string" && message.trim().length > 0) {
      return message;
    }
  }
  return fallback;
}

export async function fetchClickPesaToken(
  config: ClickPesaConfig,
): Promise<string> {
  const response = await fetch(`${config.apiBaseUrl}/generate-token`, {
    method: "POST",
    headers: {
      "client-id": config.clientId,
      "api-key": config.apiKey,
      Accept: "application/json",
    },
  });
  const payload = await parseJsonResponse(response);
  if (!response.ok) {
    throw new ClickPesaRequestError(
      extractErrorMessage(payload, "Could not get a ClickPesa access token."),
      response.status,
      payload,
    );
  }
  const token = typeof (payload as JsonRecord | null)?.token === "string"
    ? ((payload as JsonRecord).token as string)
    : "";
  if (!token) {
    throw new ClickPesaRequestError(
      "ClickPesa did not return an access token.",
      502,
      payload,
    );
  }
  return token;
}

export async function generateCheckoutLink(
  config: ClickPesaConfig,
  token: string,
  payload: JsonRecord,
): Promise<JsonRecord> {
  const response = await fetch(
    `${config.apiBaseUrl}/checkout-link/generate-checkout-url`,
    {
      method: "POST",
      headers: {
        Authorization: token,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(payload),
    },
  );
  const parsed = await parseJsonResponse(response);
  if (!response.ok) {
    throw new ClickPesaRequestError(
      extractErrorMessage(parsed, "Could not create a ClickPesa checkout link."),
      response.status,
      parsed,
    );
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new ClickPesaRequestError(
      "ClickPesa returned an invalid checkout response.",
      502,
      parsed,
    );
  }
  return parsed as JsonRecord;
}

export async function queryPaymentStatus(
  config: ClickPesaConfig,
  token: string,
  orderReference: string,
): Promise<ClickPesaPaymentStatus | null> {
  const response = await fetch(
    `${config.apiBaseUrl}/payments/${encodeURIComponent(orderReference)}`,
    {
      method: "GET",
      headers: {
        Authorization: token,
        Accept: "application/json",
      },
    },
  );
  const payload = await parseJsonResponse(response);
  if (!response.ok) {
    throw new ClickPesaRequestError(
      extractErrorMessage(payload, "Could not verify the ClickPesa payment."),
      response.status,
      payload,
    );
  }
  if (!Array.isArray(payload) || payload.length === 0) {
    return null;
  }
  const first = payload[0];
  if (!first || typeof first !== "object" || Array.isArray(first)) {
    return null;
  }
  return first as ClickPesaPaymentStatus;
}

export async function previewUssdPushRequest(
  config: ClickPesaConfig,
  token: string,
  payload: JsonRecord,
): Promise<ClickPesaPreviewResponse> {
  const response = await fetch(
    `${config.apiBaseUrl}/payments/preview-ussd-push-request`,
    {
      method: "POST",
      headers: {
        Authorization: token,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(payload),
    },
  );
  const parsed = await parseJsonResponse(response);
  if (!response.ok) {
    throw new ClickPesaRequestError(
      extractErrorMessage(
        parsed,
        "Could not preview the ClickPesa mobile money request.",
      ),
      response.status,
      parsed,
    );
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new ClickPesaRequestError(
      "ClickPesa returned an invalid mobile money preview response.",
      502,
      parsed,
    );
  }
  return parsed as ClickPesaPreviewResponse;
}

export async function initiateUssdPushRequest(
  config: ClickPesaConfig,
  token: string,
  payload: JsonRecord,
): Promise<ClickPesaInitiateResponse> {
  const response = await fetch(
    `${config.apiBaseUrl}/payments/initiate-ussd-push-request`,
    {
      method: "POST",
      headers: {
        Authorization: token,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(payload),
    },
  );
  const parsed = await parseJsonResponse(response);
  if (!response.ok) {
    throw new ClickPesaRequestError(
      extractErrorMessage(
        parsed,
        "Could not start the ClickPesa mobile money request.",
      ),
      response.status,
      parsed,
    );
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new ClickPesaRequestError(
      "ClickPesa returned an invalid mobile money payment response.",
      502,
      parsed,
    );
  }
  return parsed as ClickPesaInitiateResponse;
}

export function mapClickPesaStatus(
  status: string | null | undefined,
): "pending" | "processing" | "paid" | "failed" {
  switch ((status ?? "").toUpperCase()) {
    case "SUCCESS":
    case "SETTLED":
      return "paid";
    case "FAILED":
      return "failed";
    case "PROCESSING":
      return "processing";
    default:
      return "pending";
  }
}
