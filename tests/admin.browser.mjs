import { chromium } from "playwright";
import assert from "node:assert/strict";
import { mkdir } from "node:fs/promises";

await mkdir("work/screenshots", { recursive: true });
const browser = await chromium.launch({
  channel: process.env.BROWSER_CHANNEL ?? "msedge",
  headless: true,
});
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
const errors = [];
page.on("pageerror", (error) => errors.push(error.message));
try {
  await page.goto("http://127.0.0.1:5173/");
  const password = page.locator('input[name="password"]');
  assert.equal(await password.getAttribute("type"), "password");
  await page
    .getByRole("button", { name: "إظهار أو إخفاء كلمة المرور" })
    .click();
  assert.equal(await password.getAttribute("type"), "text");
  await page
    .getByRole("button", { name: "إظهار أو إخفاء كلمة المرور" })
    .click();
  assert.equal(await password.getAttribute("type"), "password");
  await page.getByRole("button", { name: "استعرض النسخة التجريبية" }).click();
  await page
    .getByRole("heading", { name: "كل الرحلات، تحت إدارتك." })
    .waitFor();
  assert.equal(await page.locator("html").getAttribute("dir"), "rtl");
  await page.getByRole("cell", { name: "أحمد أبو سنينة" }).waitFor();
  await page.screenshot({
    path: "work/screenshots/admin-arabic.png",
    fullPage: true,
  });
  await page.getByRole("button", { name: "English", exact: true }).click();
  await page
    .getByRole("heading", { name: "Every ride. In your hands." })
    .waitFor();
  assert.equal(await page.locator("html").getAttribute("dir"), "ltr");
  await page
    .getByRole("button", { name: "Drivers & vehicles", exact: false })
    .first()
    .click();
  await page.getByRole("cell", { name: "3-7254-19" }).waitFor();
  await page.getByRole("cell", { name: "3-7254-19" }).click();
  await page
    .getByRole("button", { name: "Approve vehicle", exact: true })
    .click();
  await page.getByRole("textbox", { name: "Capacity", exact: true }).fill("٨١");
  await page
    .getByRole("button", { name: "Confirm & save", exact: true })
    .click();
  await page
    .getByText("Enter a valid value for Capacity", { exact: true })
    .waitFor();
  await page.getByRole("textbox", { name: "Capacity", exact: true }).fill("١٩");
  await page
    .getByRole("button", { name: "Confirm & save", exact: true })
    .click();
  await page.getByRole("status").waitFor();
  const vehicleRow = page.getByRole("row").filter({ hasText: "3-7254-19" });
  await vehicleRow.locator(".status-true").waitFor();
  assert.equal(await vehicleRow.locator(".status-true").count(), 1);
  await page
    .getByRole("button", { name: "Routes & permits", exact: true })
    .click();
  await page.getByRole("button", { name: "Add route +" }).click();
  await page
    .getByRole("textbox", { name: "Arabic name", exact: true })
    .fill("السموع — رام الله");
  await page
    .getByRole("textbox", { name: "English name", exact: true })
    .fill("As Samu — Ramallah");
  await page
    .getByRole("textbox", { name: "Governorate", exact: true })
    .fill("الخليل");
  await page
    .getByRole("button", { name: "Confirm & save", exact: true })
    .click();
  await page.getByRole("cell", { name: "As Samu — Ramallah" }).waitFor();
  await page.getByPlaceholder("Search records…").fill("Ramallah");
  await page.waitForFunction(
    () => document.querySelectorAll("tbody tr").length === 1,
  );
  await page.getByRole("button", { name: "Overview", exact: true }).click();
  await page.screenshot({
    path: "work/screenshots/admin-english.png",
    fullPage: true,
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({
    path: "work/screenshots/admin-mobile.png",
    fullPage: true,
  });
  assert.equal(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
    true,
  );
  await page.getByRole("button", { name: "Menu", exact: true }).click();
  await page.getByRole("button", { name: "Accounts", exact: true }).click();
  await page
    .getByRole("heading", { name: "Accounts", exact: true })
    .first()
    .waitFor();
  assert.deepEqual(errors, []);
  console.log(
    "PASS: Arabic/English, demo approval, route creation, search, mobile navigation, no overflow or browser errors.",
  );
} finally {
  await browser.close();
}
