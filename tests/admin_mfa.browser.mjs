// Uses isolated synthetic Auth fixtures. No live account, QR secret or OTP is used.
import { chromium } from "playwright";
import assert from "node:assert/strict";
import { mkdir } from "node:fs/promises";

const browser = await chromium.launch({
  channel: process.env.BROWSER_CHANNEL ?? "msedge",
  headless: true,
});
const context = await browser.newContext();
const errors = [],
  unexpected = [];
let verified = false,
  expireChallenge = false,
  challengeCalls = 0,
  adminCalls = 0;
const id = "10000000-0000-0000-0000-000000000001",
  factorId = "20000000-0000-0000-0000-000000000001";
let factors = [];
const user = () => ({
  id,
  aud: "authenticated",
  role: "authenticated",
  email: "owner@example.test",
  email_confirmed_at: new Date().toISOString(),
  created_at: new Date().toISOString(),
  app_metadata: { provider: "email", providers: ["email"] },
  user_metadata: { full_name: "Fixture owner" },
  factors,
});
const jwt = (aal) =>
  [
    Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString(
      "base64url",
    ),
    Buffer.from(
      JSON.stringify({
        sub: id,
        role: "authenticated",
        aal,
        iat: Math.floor(Date.now() / 1000),
        exp: Math.floor(Date.now() / 1000) + 3600,
        amr: [{ method: "password", timestamp: Math.floor(Date.now() / 1000) }],
      }),
    ).toString("base64url"),
    Buffer.alloc(32, 1).toString("base64url"),
  ].join(".");
const session = () => ({
  access_token: jwt(verified ? "aal2" : "aal1"),
  refresh_token: "fixture-refresh",
  token_type: "bearer",
  expires_in: 3600,
  user: user(),
});
await context.route(/https:\/\/[^/]+\.supabase\.co\//, async (route) => {
  const req = route.request(),
    url = new URL(req.url()),
    path = url.pathname;
  const json = (body, status = 200) =>
    route.fulfill({
      status,
      contentType: "application/json",
      body: JSON.stringify(body),
    });
  if (req.method() === "OPTIONS") return route.fulfill({ status: 204 });
  if (path === "/auth/v1/token") return json(session());
  if (path === "/auth/v1/user") return json(user());
  if (path === "/auth/v1/logout") return route.fulfill({ status: 204 });
  if (path === "/auth/v1/factors" && req.method() === "POST") {
    factors = [
      {
        id: factorId,
        factor_type: "totp",
        friendly_name: "Rukkab admin",
        status: "unverified",
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      },
    ];
    return json({
      id: factorId,
      type: "totp",
      totp: {
        qr_code:
          '<svg xmlns="http://www.w3.org/2000/svg" width="180" height="180"><rect width="180" height="180" fill="teal"/></svg>',
        secret: "FIXTUREKEYONLY",
        uri: "otpauth://totp/Fixture",
      },
    });
  }
  if (path === `/auth/v1/factors/${factorId}` && req.method() === "DELETE") {
    factors = [];
    return json({});
  }
  if (path.endsWith("/challenge")) {
    challengeCalls++;
    if (expireChallenge)
      return json(
        { code: "session_not_found", msg: "Auth session missing!" },
        401,
      );
    return json({
      id: "30000000-0000-0000-0000-000000000001",
      expires_at: Math.floor(Date.now() / 1000) + 120,
    });
  }
  if (path.endsWith("/verify")) {
    if (req.postDataJSON().code !== "123456")
      return json(
        { code: "mfa_verification_failed", msg: "Invalid TOTP code entered" },
        422,
      );
    verified = true;
    factors[0].status = "verified";
    return json(session());
  }
  if (path === "/rest/v1/profiles")
    return json({
      id,
      full_name: "Fixture owner",
      role: "owner",
      disabled: false,
    });
  if (path === "/rest/v1/notifications" && req.method() === "HEAD") {
    assert.equal(
      verified,
      true,
      "Notification counts require the admin MFA gate",
    );
    assert.equal(url.searchParams.get("user_id"), `eq.${id}`);
    assert.equal(url.searchParams.get("read_at"), "is.null");
    return route.fulfill({
      status: 200,
      headers: { "content-range": "*/3" },
      body: "",
    });
  }
  if (path.startsWith("/rest/v1/rpc/")) {
    adminCalls++;
    return json(
      path.endsWith("admin_overview")
        ? {
            riders: 0,
            drivers: 0,
            active_trips: 0,
            today_bookings: 0,
            week: [],
          }
        : { rows: [], total: 0 },
    );
  }
  unexpected.push(`${req.method()} ${path}`);
  return route.abort();
});
await context.routeWebSocket(/supabase\.co/, (socket) => socket.close());
const page = await context.newPage();
page.on("pageerror", (e) => errors.push(e.message));
try {
  const otherTab = await context.newPage();
  await otherTab.goto("http://127.0.0.1:5173/");
  await otherTab
    .getByRole("heading", { name: "أهلًا في مركز الإدارة" })
    .waitFor();
  await page.goto("http://127.0.0.1:5173/");
  await page
    .getByRole("textbox", { name: "البريد الإلكتروني", exact: true })
    .fill("owner@example.test");
  await page.locator('input[name="password"]').fill("Fixture-password-only");
  await page.getByRole("button", { name: "تسجيل الدخول", exact: true }).click();
  await page.getByRole("button", { name: "إعداد المصادقة الثنائية" }).waitFor();
  assert.equal(adminCalls, 0, "AAL1 must never load administrative data");
  assert.equal(
    await otherTab
      .getByRole("heading", { name: "أهلًا في مركز الإدارة" })
      .count(),
    1,
  );
  assert.equal(
    await page.evaluate(() => localStorage.getItem("rukkab-admin-auth")),
    null,
  );
  await page.reload();
  await page.getByRole("button", { name: "إعداد المصادقة الثنائية" }).waitFor();
  await page.getByRole("button", { name: "إعداد المصادقة الثنائية" }).click();
  await page.getByRole("img", { name: "رمز إعداد تطبيق المصادقة" }).waitFor();
  await page.getByText("نفس الهاتف؟ استخدم مفتاح الإعداد اليدوي").click();
  await page.getByText("FIXTUREKEYONLY", { exact: true }).waitFor();
  const code = page.getByRole("textbox", { name: "Verification code" });
  await code.fill("000000");
  await page.getByRole("button", { name: "تحقق", exact: true }).click();
  await page
    .getByRole("alert")
    .filter({ hasText: "رمز التحقق غير صحيح" })
    .waitFor();
  assert.equal(adminCalls, 0);
  expireChallenge = true;
  await code.fill("١٢٣٤٥٦");
  assert.equal(await code.inputValue(), "123456");
  await page.getByRole("button", { name: "تحقق", exact: true }).click();
  await page.getByRole("button", { name: "العودة لتسجيل الدخول" }).waitFor();
  await page.getByRole("button", { name: "العودة لتسجيل الدخول" }).click();
  await page.getByRole("heading", { name: "أهلًا في مركز الإدارة" }).waitFor();
  assert.equal(
    await page.evaluate(() => sessionStorage.getItem("rukkab-admin-auth")),
    null,
  );
  expireChallenge = false;
  await page
    .getByRole("textbox", { name: "البريد الإلكتروني", exact: true })
    .fill("owner@example.test");
  await page.locator('input[name="password"]').fill("Fixture-password-only");
  await page.getByRole("button", { name: "تسجيل الدخول", exact: true }).click();
  await page.getByRole("button", { name: "إعداد المصادقة الثنائية" }).waitFor();
  await page.getByRole("button", { name: "إعداد المصادقة الثنائية" }).click();
  await page.getByRole("textbox", { name: "Verification code" }).fill("123456");
  const overviewLoaded = page.waitForResponse(
    (response) =>
      new URL(response.url()).pathname === "/rest/v1/rpc/admin_overview",
  );
  await page.getByRole("button", { name: "تحقق", exact: true }).click();
  await page
    .getByRole("heading", { name: "كل الرحلات، تحت إدارتك." })
    .waitFor();
  await overviewLoaded;
  assert.ok(adminCalls > 0);
  assert.equal(
    await otherTab
      .getByRole("heading", { name: "أهلًا في مركز الإدارة" })
      .count(),
    1,
    "Auth broadcast must not sign another tab in without its own stored session",
  );
  assert.equal(challengeCalls, 3);
  await page.reload();
  await page
    .getByRole("heading", { name: "كل الرحلات، تحت إدارتك." })
    .waitFor();
  assert.deepEqual(errors, []);
  assert.deepEqual(unexpected, []);
  console.log(
    "PASS: tab-scoped reload persistence, AAL1 gate, manual setup, invalid code, expired session recovery, Arabic digits, AAL2 entry and reload. Auth network is fully mocked.",
  );
} catch (failure) {
  console.error({ errors, unexpected, verified, challengeCalls, adminCalls });
  throw failure;
} finally {
  await browser.close();
}
