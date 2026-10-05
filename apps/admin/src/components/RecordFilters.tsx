import { useState, useEffect } from "react";
import type { Table } from "../data";
import type {
  RecordFilters as FilterValues,
  RecordSort,
} from "../core/record_filters";
type Field = [string, string, string, string[]];
const fields: Partial<Record<Table, Field[]>> = {
  profiles: [
    ["role", "الدور", "Role", ["rider", "driver", "operator", "owner"]],
    ["disabled", "الحساب موقوف", "Disabled", ["true", "false"]],
  ],
  vehicles: [
    [
      "application_state",
      "طلب السائق",
      "Application",
      ["draft", "submitted", "approved", "rejected"],
    ],
    [
      "kind",
      "نوع السيارة",
      "Vehicle type",
      ["taxi", "minibus", "medium_bus", "large_bus"],
    ],
    ["approved", "الاعتماد", "Approved", ["true", "false"]],
    ["online", "متصل للعمل", "Online", ["true", "false"]],
  ],
  documents: [
    [
      "kind",
      "نوع الوثيقة",
      "Document",
      ["license", "permit", "insurance", "registration", "vehicle_photo"],
    ],
    ["verified", "التحقق", "Verified", ["true", "false"]],
    [
      "renewal_required",
      "يتطلب تجديدًا",
      "Renewal required",
      ["true", "false"],
    ],
  ],
  trips: [
    [
      "state",
      "حالة الرحلة",
      "Trip status",
      ["published", "active", "completed", "cancelled"],
    ],
    ["service", "الخدمة", "Service", ["shared", "private"]],
  ],
  bookings: [
    [
      "state",
      "حالة الحجز",
      "Booking status",
      [
        "pending",
        "confirmed",
        "boarded",
        "completed",
        "cancelled",
        "rejected",
        "no_show",
        "reschedule_pending",
      ],
    ],
    ["service", "الخدمة", "Service", ["shared", "private"]],
  ],
  ride_requests: [
    [
      "state",
      "حالة الطلب",
      "Request status",
      ["searching", "offered", "booked", "expired", "cancelled"],
    ],
    ["service", "الخدمة", "Service", ["shared", "private"]],
  ],
  appeals: [
    [
      "state",
      "حالة الاعتراض",
      "Appeal status",
      ["pending", "accepted", "rejected"],
    ],
  ],
  routes: [["active", "الخط مفعل", "Active", ["true", "false"]]],
};
export function RecordFilters({
  table,
  en,
  values,
  sort,
  onApply,
  t,
}: {
  table: Table;
  en: boolean;
  values: FilterValues;
  sort: RecordSort;
  onApply: (values: FilterValues, sort: RecordSort) => void;
  t: (key: string) => string;
}) {
  const [draft, setDraft] = useState(values),
    [order, setOrder] = useState(sort);
  useEffect(() => {
    setDraft(values);
    setOrder(sort);
  }, [values, sort, table]);
  const text = (ar: string, english: string) => (en ? english : ar);
  const dateLabel =
    table === "documents"
      ? text("انتهاء الوثيقة", "Document expiry")
      : table === "trips"
        ? text("انطلاق الرحلة", "Departure")
        : table === "vehicle_locations"
          ? text("تحديث الموقع", "Location update")
          : text("إنشاء السجل", "Record creation");
  const set = (key: string, value: string, boolean = false) =>
    setDraft((current) => {
      const next = { ...current };
      if (value === "") delete next[key];
      else next[key] = boolean ? value === "true" : value;
      return next;
    });
  return (
    <form
      className="filter-controls"
      onSubmit={(event) => {
        event.preventDefault();
        onApply(draft, order);
      }}
    >
      {(fields[table] ?? []).map(([key, ar, english, options]) => (
        <label key={key}>
          {text(ar, english)}
          <select
            aria-label={text(ar, english)}
            value={String(draft[key] ?? "")}
            onChange={(event) =>
              set(
                key,
                event.target.value,
                [
                  "disabled",
                  "approved",
                  "online",
                  "verified",
                  "renewal_required",
                  "active",
                ].includes(key),
              )
            }
          >
            <option value="">{text("الكل", "All")}</option>
            {options.map((option) => (
              <option key={option} value={option}>
                {option === "true"
                  ? text("نعم", "Yes")
                  : option === "false"
                    ? text("لا", "No")
                    : t(option)}
              </option>
            ))}
          </select>
        </label>
      ))}
      {table !== "settings" && (
        <p className="muted filter-date-hint">
          {dateLabel} · {text("بتوقيت فلسطين", "Palestine time")}
        </p>
      )}
      {table !== "settings" &&
        ["from", "to"].map((key) => (
          <label key={key}>
            {text(
              key === "from" ? "من تاريخ" : "إلى تاريخ",
              key === "from" ? "From date" : "To date",
            )}
            <input
              type="date"
              aria-label={text(
                key === "from" ? "من تاريخ" : "إلى تاريخ",
                key === "from" ? "From date" : "To date",
              )}
              value={String(draft[key] ?? "")}
              onChange={(event) => set(key, event.target.value)}
            />
          </label>
        ))}
      <label>
        {text("ترتيب النتائج", "Sort results")}
        <select
          aria-label={text("ترتيب النتائج", "Sort results")}
          value={order}
          onChange={(event) => setOrder(event.target.value as RecordSort)}
        >
          <option value="newest">{text("الأحدث أولًا", "Newest first")}</option>
          <option value="oldest">{text("الأقدم أولًا", "Oldest first")}</option>
          <option value="name">
            {text("حسب الاسم أو النمرة", "By name or plate")}
          </option>
          {table === "vehicles" && (
            <option value="capacity">
              {text("السعة الأكبر", "Largest capacity")}
            </option>
          )}
          {["trips", "bookings", "offers"].includes(table) && (
            <option value="price">{text("السعر الأقل", "Lowest price")}</option>
          )}
        </select>
      </label>
      <button className="primary" type="submit">
        {text("تطبيق الفلاتر", "Apply filters")}
      </button>
      <button
        className="secondary"
        type="button"
        onClick={() => onApply({}, "newest")}
      >
        {text("مسح الفلاتر", "Reset filters")}
      </button>
    </form>
  );
}
