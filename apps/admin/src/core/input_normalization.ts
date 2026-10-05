// Keep Arabic names untouched; normalize only fields that carry numeric values.
export function parseAdminNumber(field: string, value: unknown): number {
  const text = String(value ?? "")
    .trim()
    .replace(/[٠-٩]/g, (digit) => String(digit.charCodeAt(0) - 0x0660))
    .replace(/[۰-۹]/g, (digit) => String(digit.charCodeAt(0) - 0x06f0))
    .replaceAll("٫", ".")
    .replaceAll("−", "-");
  if (!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/.test(text))
    throw new Error("INVALID_NUMBER");
  const number = Number(text);
  if (!Number.isFinite(number)) throw new Error("INVALID_NUMBER");
  if (
    field === "capacity" &&
    (!Number.isInteger(number) || number < 1 || number > 80)
  )
    throw new Error("INVALID_CAPACITY");
  if (
    field === "sequence" &&
    (!Number.isInteger(number) || number < 0 || number > 2147483647)
  )
    throw new Error("INVALID_SEQUENCE");
  if (field === "latitude" && (number < -90 || number > 90))
    throw new Error("INVALID_COORDINATE");
  if (field === "longitude" && (number < -180 || number > 180))
    throw new Error("INVALID_COORDINATE");
  return number;
}
