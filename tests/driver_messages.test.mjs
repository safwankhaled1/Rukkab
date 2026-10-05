import { test } from "node:test";
import assert from "node:assert/strict";
import {
  driverNoticeMessage,
  driverNoticeTitle,
} from "../supabase/functions/send-notifications/driver-messages.ts";
test("Driver review notice states count and window in both languages and keeps submission copy", () => {
  const body = JSON.stringify({
    full_name: "سائق اختبار",
    count: 3,
    window_days: 30,
  });
  assert.match(
    driverNoticeMessage("driver.cancellation_review", body, false),
    /3 إلغاءات خلال 30/,
  );
  assert.match(
    driverNoticeMessage("driver.cancellation_review", body, true),
    /3 cancellations in 30 days/,
  );
  assert.equal(
    driverNoticeMessage("driver.application_submitted", body, true),
    "Completed driver application: سائق اختبار",
  );
  assert.equal(
    driverNoticeMessage(
      "driver.application_received",
      JSON.stringify({ plate: "TEST-1" }),
      false,
    ),
    "تم استلام طلب السائق: TEST-1",
  );
});
test("Malformed driver notices have a readable fallback and never invent a review count", () => {
  for (const body of [
    "not-json",
    "null",
    "{}",
    '{"count":"NaN","window_days":30}',
    '{"full_name":{},"count":3,"window_days":null}',
  ]) {
    assert.equal(
      driverNoticeMessage("driver.cancellation_review", body, true),
      driverNoticeTitle("driver.cancellation_review", true),
    );
  }
});
