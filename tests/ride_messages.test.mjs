import { test } from "node:test";
import assert from "node:assert/strict";
import { rideMessage } from "../supabase/functions/send-notifications/ride-messages.ts";
test("Booking refusal and reschedule consent explain the result and preserve the right to appeal", () => {
  assert.match(rideMessage("booking.reject", true), /declined.*another trip/);
  assert.match(rideMessage("booking.accept_time", true), /accepted.*confirmed/);
  assert.match(
    rideMessage("booking.decline_time", true),
    /cancelled without a violation/,
  );
  assert.match(
    rideMessage("booking.decline_time", false),
    /أُلغي الحجز دون مخالفة/,
  );
  assert.match(rideMessage("booking.no_show", false), /يمكنك الاعتراض/);
  assert.match(rideMessage("booking.no_show", true), /appeal/);
});
test("Operational ride notifications identify progress in both languages", () => {
  for (const kind of [
    "booking.pickup",
    "booking.board",
    "booking.alight",
    "trip.pickup",
    "trip.finish",
    "offer.accepted",
  ]) {
    assert.notEqual(rideMessage(kind, false), rideMessage("unknown", false));
    assert.notEqual(rideMessage(kind, true), rideMessage("unknown", true));
    assert.match(rideMessage(kind, false), /[\u0600-\u06ff]/);
  }
});
