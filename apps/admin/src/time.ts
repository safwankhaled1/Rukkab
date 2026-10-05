export function toPalestineInput(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return new Intl.DateTimeFormat("sv-SE", {
    timeZone: "Asia/Hebron",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  })
    .format(date)
    .replace(" ", "T");
}
export function fromPalestineInput(value: string) {
  const [y, m, d, h, min] = value.split(/[-T:]/).map(Number);
  const target = Date.UTC(y, m - 1, d, h, min);
  let utc = target;
  for (let i = 0; i < 3; i++) {
    const parts = toPalestineInput(new Date(utc).toISOString())
      .split(/[-T:]/)
      .map(Number);
    const local = Date.UTC(
      parts[0],
      parts[1] - 1,
      parts[2],
      parts[3],
      parts[4],
    );
    utc += target - local;
  }
  if (toPalestineInput(new Date(utc).toISOString()) !== value)
    throw new Error("INVALID_LOCAL_TIME");
  return new Date(utc).toISOString();
}
