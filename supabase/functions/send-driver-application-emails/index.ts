import { createClient } from "npm:@supabase/supabase-js@2";

type Job = {
  id: string;
  lease: string;
  email: string;
  plate: string;
  attempts: number;
};
const encoder = new TextEncoder();
async function matches(a: string, b: string) {
  const left = new Uint8Array(
    await crypto.subtle.digest("SHA-256", encoder.encode(a)),
  );
  const right = new Uint8Array(
    await crypto.subtle.digest("SHA-256", encoder.encode(b)),
  );
  let difference = 0;
  for (let index = 0; index < left.length; index++)
    difference |= left[index] ^ right[index];
  return difference === 0;
}

// Secrets remain server-side. Missing provider configuration does not consume jobs.
Deno.serve(async (request) => {
  const workerSecret = Deno.env.get("APPLICATION_EMAIL_WORKER_SECRET");
  if (
    request.method !== "POST" ||
    !workerSecret ||
    !(await matches(
      request.headers.get("x-rukkab-worker-secret") ?? "",
      workerSecret,
    ))
  ) {
    return new Response("Unauthorized", { status: 401 });
  }
  const url = Deno.env.get("SUPABASE_URL"),
    key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
    apiKey = Deno.env.get("RESEND_API_KEY"),
    sender = Deno.env.get("APPLICATION_EMAIL_FROM");
  if (!url || !key || !apiKey || !sender) {
    return new Response("Mail configuration missing", { status: 503 });
  }
  const client = createClient(url, key, { auth: { persistSession: false } });
  try {
    const { data, error } = await client.rpc("claim_driver_application_emails");
    if (error) throw error;
    let accepted = 0,
      failed = 0;
    for (const job of data as Job[]) {
      let success = false;
      try {
        const response = await fetch("https://api.resend.com/emails", {
          method: "POST",
          signal: AbortSignal.timeout(15000),
          headers: {
            Authorization: `Bearer ${apiKey}`,
            "Content-Type": "application/json",
            "Idempotency-Key": `driver-application/${job.id}`,
          },
          body: JSON.stringify({
            from: sender,
            to: [job.email],
            subject: "ركاب — استلمنا طلب تسجيلك كسائق",
            text: `مرحبًا،\n\nاستلمنا طلب تسجيلك كسائق للسيارة ${job.plate}. الطلب قيد المراجعة لدى إدارة ركاب. سنبلغك بالنتيجة داخل التطبيق. لا يمكنك استقبال الحجوزات قبل الاعتماد.\n\nفريق ركاب\n\nYour driver application for vehicle ${job.plate} was received and is under review. You will receive the decision in the app.`,
          }),
        });
        success = response.ok;
      } catch {
        success = false;
      }
      const { error: finishError } = await client.rpc(
        "finish_driver_application_email",
        { job: job.id, token: job.lease, success },
      );
      if (finishError) throw finishError;
      if (success) accepted++;
      else failed++;
    }
    return Response.json({ accepted, failed });
  } catch {
    // Do not return provider responses, recipient addresses or secret-bearing logs.
    return new Response("Mail worker failed", { status: 500 });
  }
});
