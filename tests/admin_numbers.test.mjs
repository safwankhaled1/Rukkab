import { test } from "node:test";
import assert from "node:assert/strict";
import { parseAdminNumber } from "../apps/admin/src/core/input_normalization.ts";
test("Admin accepts Arabic/Persian numbers without allowing invalid seat limits or coordinates", () => {
  assert.equal(parseAdminNumber("capacity", "١٩"), 19);
  assert.equal(parseAdminNumber("capacity", "۵۵"), 55);
  assert.equal(parseAdminNumber("latitude", "٣١٫٤"), 31.4);
  assert.equal(parseAdminNumber("longitude", "−۳۵٫۰۷"), -35.07);
  for (const invalid of ["", " ", "abc", "Infinity", "1e99", "١٩x", "NaN"])
    assert.throws(() => parseAdminNumber("capacity", invalid));
  for (const invalid of ["٠", "٨١", "١٫٥"])
    assert.throws(() => parseAdminNumber("capacity", invalid));
  assert.throws(() => parseAdminNumber("latitude", "٩١"));
  assert.throws(() => parseAdminNumber("longitude", "١٨١"));
  assert.throws(() => parseAdminNumber("sequence", "−١"));
});
