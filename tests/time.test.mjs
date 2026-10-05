import { test } from "node:test";
import assert from "node:assert/strict";
import {
  toPalestineInput,
  fromPalestineInput,
} from "../apps/admin/src/time.ts";
test("admin dates round-trip in Palestine time independently of workstation timezone", () => {
  for (const value of ["2026-01-15T08:00", "2026-07-15T08:00"]) {
    assert.equal(toPalestineInput(fromPalestineInput(value)), value);
    assert.notEqual(fromPalestineInput(value), `${value}:00.000Z`);
  }
});
