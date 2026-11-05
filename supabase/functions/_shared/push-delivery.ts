// Invalid payloads and transient failures must not revoke valid installations.
export function isUnregisteredDevice(payload: unknown): boolean {
  const details = (payload as { error?: { details?: unknown } })?.error
    ?.details;
  return Array.isArray(details) &&
    details.some((detail) =>
      detail?.["@type"] ===
        "type.googleapis.com/google.firebase.fcm.v1.FcmError" &&
      detail.errorCode === "UNREGISTERED"
    );
}

export function deliveryComplete(
  messageIds: string[],
  transientErrors: string[],
): boolean {
  return messageIds.length > 0 && transientErrors.length === 0;
}
