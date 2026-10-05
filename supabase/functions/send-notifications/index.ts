import { createClient } from "npm:@supabase/supabase-js@2";
import { rideMessage } from "./ride-messages.ts";
import { driverNoticeMessage } from "./driver-messages.ts";
import { documentMessage } from "./document-messages.ts";

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};
type Job = {
  id: string;
  attempts: number;
  kind: string;
  body: string;
  booking_id: string | null;
  language: string;
  tokens: string[];
};
const encoder = new TextEncoder();
const base64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes))
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
const encode = (value: unknown) =>
  base64url(encoder.encode(JSON.stringify(value)));
async function equals(a: string, b: string) {
  const aa = new Uint8Array(
      await crypto.subtle.digest("SHA-256", encoder.encode(a)),
    ),
    bb = new Uint8Array(
      await crypto.subtle.digest("SHA-256", encoder.encode(b)),
    );
  let diff = 0;
  for (let i = 0; i < aa.length; i++) diff |= aa[i] ^ bb[i];
  return diff === 0;
}
async function accessToken(account: ServiceAccount) {
  const pem = account.private_key
    .replace(/-----[^-]+-----/g, "")
    .replace(/\s/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const now = Math.floor(Date.now() / 1000);
  const content = `${encode({ alg: "RS256", typ: "JWT" })}.${encode({ iss: account.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging", aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600 })}`;
  const signature = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, encoder.encode(content)),
  );
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${content}.${base64url(signature)}`,
    }),
  });
  if (!response.ok) throw new Error("FCM_AUTH_FAILED");
  return (await response.json()).access_token as string;
}
Deno.serve(async (request) => {
  const secret = Deno.env.get("NOTIFICATION_WORKER_SECRET");
  if (
    request.method !== "POST" ||
    !secret ||
    !(await equals(request.headers.get("x-rukkab-worker-secret") ?? "", secret))
  )
    return new Response("Unauthorized", { status: 401 });
  const url = Deno.env.get("SUPABASE_URL"),
    key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
    rawAccount = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!url || !key || !rawAccount)
    return new Response("Worker configuration missing", { status: 503 });
  const client = createClient(url, key, { auth: { persistSession: false } });
  try {
    const account = JSON.parse(rawAccount) as ServiceAccount;
    const oauth = await accessToken(account);
    const { data, error } = await client.rpc("claim_notifications");
    if (error) throw error;
    let sent = 0,
      failed = 0;
    for (const job of data as Job[]) {
      let ok = true;
      const body = job.kind.startsWith("document.")
        ? documentMessage(job.kind, job.body, job.language === "en")
        : job.kind.startsWith("driver.")
          ? driverNoticeMessage(job.kind, job.body, job.language === "en")
          : job.kind === "admin.message"
            ? job.body
            : rideMessage(job.kind, job.language === "en");
      for (const token of job.tokens) {
        try {
          const response = await fetch(
            `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
            {
              method: "POST",
              headers: {
                Authorization: `Bearer ${oauth}`,
                "Content-Type": "application/json",
              },
              body: JSON.stringify({
                message: {
                  token,
                  notification: { title: "ركاب | Rukkab", body },
                  data: {
                    kind: job.kind,
                    ...(job.booking_id ? { booking_id: job.booking_id } : {}),
                  },
                  android: { priority: "high" },
                },
              }),
            },
          );
          if (!response.ok) {
            const result = await response.json();
            const permanent = result.error?.details?.some(
              (x: { errorCode?: string }) => x.errorCode === "UNREGISTERED",
            );
            if (permanent)
              await client.from("device_tokens").delete().eq("token", token);
            else ok = false;
          }
        } catch {
          ok = false;
        }
      }
      await client.rpc("finish_notification", {
        jid: job.id,
        success: ok,
        err: ok ? null : "FCM_DELIVERY_FAILED",
      });
      if (ok) sent++;
      else failed++;
    }
    return Response.json({ sent, failed });
  } catch {
    return new Response("Notification delivery unavailable", { status: 503 });
  }
});
