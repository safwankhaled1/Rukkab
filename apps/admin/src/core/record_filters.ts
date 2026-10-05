import type { Row, Table } from "../data";
export type RecordFilters = Record<string, string | boolean>;
export type RecordSort = "newest" | "oldest" | "name" | "capacity" | "price";
export function filterDemoRows(
  rows: Row[],
  search: string,
  filters: RecordFilters,
  sort: RecordSort,
  table: Table,
) {
  const day = (value: unknown) =>
    value == null
      ? ""
      : new Intl.DateTimeFormat("en-CA", {
          timeZone: "Asia/Hebron",
          year: "numeric",
          month: "2-digit",
          day: "2-digit",
        }).format(new Date(String(value)));
  const dateKey =
    table === "documents"
      ? "expires_on"
      : table === "trips"
        ? "starts_at"
        : table === "vehicle_locations" ? "updated_at" : "created_at";
  const found = rows.filter(
    (row) =>
      JSON.stringify(row).toLowerCase().includes(search.toLowerCase()) &&
      Object.entries(filters).every(([key, value]) => {
        if (key === "from" || key === "to") {
          const date =
            dateKey === "expires_on"
              ? String(row[dateKey] ?? "")
              : day(row[dateKey]);
          return (
            !!date &&
            (key === "from" ? date >= String(value) : date <= String(value))
          );
        }
        return row[key] === value;
      }),
  );
  const nameKey =
    table === "profiles"
      ? "full_name"
      : table === "vehicles"
        ? "plate"
        : table === "routes" || table === "stops"
          ? "name_ar"
          : "id";
  return found.sort((a, b) =>
    sort === "name"
      ? String(a[nameKey] ?? "").localeCompare(String(b[nameKey] ?? ""))
      : sort === "capacity"
        ? Number(b.capacity) - Number(a.capacity)
        : sort === "price"
          ? Number(a.price ?? a.total_price) - Number(b.price ?? b.total_price)
          : (sort === "oldest" ? 1 : -1) *
            String(a.created_at ?? "").localeCompare(
              String(b.created_at ?? ""),
            ),
  );
}
// Spreadsheet applications must treat exported user input as text, not formulas.
export function recordsCsv(rows: Row[], keys: string[], label: (key:string)=>string) {
  const cell=(value:unknown) => {
    let text=value==null?'':typeof value==='object'?JSON.stringify(value):String(value);
    if(/^\s*[=+@-]/.test(text)) text="'"+text;
    return '"'+text.replaceAll('"','""')+'"';
  };
  return '\ufeff'+[keys.map(key=>cell(label(key))).join(','),...rows.map(row=>keys.map(key=>cell(row[key+'_label']??row[key])).join(','))].join('\r\n');
}
