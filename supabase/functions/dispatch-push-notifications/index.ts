import { createClient } from "npm:@supabase/supabase-js@2";

const MAX_ATTEMPTS = 8;
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
const b64url = (value: string | Uint8Array) => {
  const bytes = typeof value === "string"
    ? new TextEncoder().encode(value)
    : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/g,
    "",
  );
};
const retryAt = (attempt: number) =>
  new Date(
    Date.now() + Math.min(15 * 2 ** Math.max(0, attempt - 1), 3600) * 1000,
  ).toISOString();

async function accessToken() {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_B64") ?? "";
  if (!raw) throw new Error("Firebase service account is not configured");
  const account = JSON.parse(atob(raw));
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = String(account.private_key).replace(
    /-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g,
    "",
  );
  const der = Uint8Array.from(
    atob(pem),
    (character) => character.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(`${header}.${claims}`),
    ),
  );
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claims}.${b64url(signature)}`,
    }),
  });
  const payload = await response.json();
  if (!response.ok || !payload.access_token) {
    throw new Error(
      payload.error_description ?? "Could not authorize Firebase messaging",
    );
  }
  return payload.access_token as string;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  const db = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  try {
    const now = new Date().toISOString();
    const staleBefore = new Date(Date.now() - 5 * 60 * 1000).toISOString();
    await db.from("notification_delivery_outbox").update({
      status: "failed",
      terminal_at: now,
      processed_at: now,
      last_error: "Delivery stopped after the maximum number of attempts",
      updated_at: now,
    }).eq("status", "processing").is("terminal_at", null)
      .gte("attempt_count", MAX_ATTEMPTS).lt("updated_at", staleBefore);
    await db.from("notification_delivery_outbox").update({
      status: "failed",
      next_attempt_at: now,
      last_error: "Recovered after an interrupted delivery attempt",
      updated_at: now,
    }).eq("status", "processing").is("terminal_at", null).lt(
      "updated_at",
      staleBefore,
    );

    const { data: jobs, error } = await db.from("notification_delivery_outbox")
      .select("id,notification_id,user_id,attempt_count")
      .in("status", ["pending", "failed"])
      .is("terminal_at", null)
      .lt("attempt_count", MAX_ATTEMPTS)
      .lte("next_attempt_at", now)
      .order("created_at")
      .limit(30);
    if (error) throw error;
    if (!jobs?.length) return json({ success: true, processed: 0 });

    const token = await accessToken();
    let sent = 0;
    let failed = 0;
    let skipped = 0;
    for (const job of jobs) {
      const attempt = Number(job.attempt_count ?? 0) + 1;
      const claimedAt = new Date().toISOString();
      const { data: claimed } = await db.from("notification_delivery_outbox")
        .update({
          status: "processing",
          attempt_count: attempt,
          last_attempt_at: claimedAt,
          updated_at: claimedAt,
        })
        .eq("id", job.id)
        .eq("attempt_count", job.attempt_count)
        .in("status", ["pending", "failed"])
        .is("terminal_at", null)
        .select("id")
        .maybeSingle();
      if (!claimed) continue;

      try {
        const [
          { data: notification },
          { data: devices },
          { data: preferences },
        ] = await Promise.all([
          db.from("notifications").select("title,body,payload,type")
            .eq("id", job.notification_id).single(),
          db.from("device_tokens").select("id,device_token")
            .eq("user_id", job.user_id).eq("is_enabled", true),
          db.from("notification_preferences")
            .select(
              "chat_enabled,requests_enabled,payments_enabled,reminders_enabled,promotions_enabled",
            )
            .eq("user_id", job.user_id).maybeSingle(),
        ]);
        if (!notification || !devices?.length) {
          const terminalAt = new Date().toISOString();
          await db.from("notification_delivery_outbox").update({
            status: "skipped",
            processed_at: terminalAt,
            terminal_at: terminalAt,
            last_error: "No active device",
            updated_at: terminalAt,
          }).eq("id", job.id);
          skipped++;
          continue;
        }

        const payload = (notification.payload ?? {}) as Record<string, unknown>;
        const event = String(payload.eventType ?? notification.type ?? "");
        const allowed = event.includes("chat")
          ? preferences?.chat_enabled !== false
          : event.includes("payment")
          ? preferences?.payments_enabled !== false
          : event.includes("reminder") || event.includes("viewing")
          ? preferences?.reminders_enabled !== false
          : event.includes("promotion") || event.includes("price")
          ? preferences?.promotions_enabled !== false
          : preferences?.requests_enabled !== false;
        if (!allowed) {
          const terminalAt = new Date().toISOString();
          await db.from("notification_delivery_outbox").update({
            status: "skipped",
            processed_at: terminalAt,
            terminal_at: terminalAt,
            last_error: "Disabled by user preference",
            updated_at: terminalAt,
          }).eq("id", job.id);
          skipped++;
          continue;
        }

        const messageIds: string[] = [];
        const transientErrors: string[] = [];
        for (const device of devices) {
          const data: Record<string, string> = {
            notificationId: job.notification_id,
          };
          for (const [key, value] of Object.entries(payload)) {
            data[key] = typeof value === "string"
              ? value
              : JSON.stringify(value);
          }
          const response = await fetch(
            `https://fcm.googleapis.com/v1/projects/${
              Deno.env.get("FIREBASE_PROJECT_ID") ?? "kodimali"
            }/messages:send`,
            {
              method: "POST",
              headers: {
                Authorization: `Bearer ${token}`,
                "Content-Type": "application/json",
              },
              body: JSON.stringify({
                message: {
                  token: device.device_token,
                  notification: {
                    title: notification.title,
                    body: notification.body,
                  },
                  data,
                  android: {
                    priority: "high",
                    notification: {
                      channel_id: data.eventType?.includes("chat")
                        ? "kodimali_chat"
                        : "kodimali_updates",
                      sound: "default",
                    },
                  },
                  apns: {
                    payload: {
                      aps: { sound: "default", "content-available": 1 },
                    },
                  },
                },
              }),
            },
          );
          const firebasePayload = await response.json();
          if (response.ok && firebasePayload.name) {
            messageIds.push(firebasePayload.name);
          } else if (response.status === 400 || response.status === 404) {
            await db.from("device_tokens").update({ is_enabled: false }).eq(
              "id",
              device.id,
            );
          } else {
            transientErrors.push(`Firebase HTTP ${response.status}`);
          }
        }

        const updateTime = new Date().toISOString();
        if (messageIds.length) {
          await db.from("notification_delivery_outbox").update({
            status: "sent",
            firebase_message_ids: messageIds,
            processed_at: updateTime,
            terminal_at: updateTime,
            last_error: transientErrors.length
              ? transientErrors.join("; ")
              : null,
            updated_at: updateTime,
          }).eq("id", job.id);
          sent++;
        } else {
          const exhausted = attempt >= MAX_ATTEMPTS;
          await db.from("notification_delivery_outbox").update({
            status: "failed",
            last_error: transientErrors.join("; ") ||
              "Firebase rejected every device",
            next_attempt_at: retryAt(attempt),
            terminal_at: exhausted ? updateTime : null,
            processed_at: exhausted ? updateTime : null,
            updated_at: updateTime,
          }).eq("id", job.id);
          failed++;
        }
      } catch (error) {
        const exhausted = attempt >= MAX_ATTEMPTS;
        const updateTime = new Date().toISOString();
        await db.from("notification_delivery_outbox").update({
          status: "failed",
          last_error: error instanceof Error ? error.message : String(error),
          next_attempt_at: retryAt(attempt),
          terminal_at: exhausted ? updateTime : null,
          processed_at: exhausted ? updateTime : null,
          updated_at: updateTime,
        }).eq("id", job.id);
        failed++;
      }
    }
    return json({
      success: true,
      processed: sent + failed + skipped,
      sent,
      failed,
      skipped,
    });
  } catch (error) {
    return json({
      error: error instanceof Error ? error.message : String(error),
    }, 500);
  }
});
