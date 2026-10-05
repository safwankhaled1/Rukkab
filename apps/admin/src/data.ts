import { createClient } from "@supabase/supabase-js";
export type Row = Record<string, unknown>;
const env = (import.meta as unknown as { env: Record<string, string> }).env;
export const supabase =
  env.VITE_SUPABASE_URL && env.VITE_SUPABASE_ANON_KEY
    ? createClient(env.VITE_SUPABASE_URL, env.VITE_SUPABASE_ANON_KEY, {
        // Survive refreshes during MFA; keep credentials scoped to this browser tab.
        auth: {
          persistSession: true,
          storage: window.sessionStorage,
          storageKey: "rukkab-admin-auth",
          autoRefreshToken: true,
        },
      })
    : null;
export const demoDefault = env.VITE_DEMO_MODE === "true";
export const tables = [
  "profiles",
  "vehicles",
  "documents",
  "routes",
  "stops",
  "trips",
  "bookings",
  "ride_requests",
  "offers",
  "vehicle_locations",
  "violations",
  "appeals",
  "notifications",
  "audit_log",
  "settings",
] as const;
export type Table = (typeof tables)[number];
const now = new Date();
const ago = (hours: number) =>
  new Date(now.getTime() - hours * 3600000).toISOString();
export const demoData: Record<Table, Row[]> = {
  profiles: [
    {
      id: "rider-1",
      full_name: "أحمد أبو سنينة",
      role: "rider",
      language: "ar",
      disabled: false,
      created_at: ago(4),
    },
    {
      id: "driver-1",
      full_name: "محمد الحوامدة",
      role: "driver",
      language: "ar",
      disabled: false,
      created_at: ago(24),
    },
    {
      id: "driver-2",
      full_name: "خالد النواجعة",
      role: "driver",
      language: "ar",
      disabled: false,
      created_at: ago(48),
    },
    {
      id: "rider-2",
      full_name: "سارة الجعبري",
      role: "rider",
      language: "ar",
      disabled: false,
      created_at: ago(8),
    },
  ],
  vehicles: [
    {
      id: "vehicle-1",
      driver_id: "driver-1",
      plate: "3-4821-71",
      application_state: "approved",
      kind: "minibus",
      capacity: 7,
      approved: true,
      online: true,
      created_at: ago(24),
    },
    {
      id: "vehicle-2",
      driver_id: "driver-2",
      plate: "3-7254-19",
      application_state: "submitted",
      kind: "medium_bus",
      capacity: 19,
      approved: false,
      online: false,
      created_at: ago(1),
    },
  ],
  documents: [
    "license",
    "permit",
    "insurance",
    "registration",
    "vehicle_photo",
  ].map((kind, i) => ({
    id: `document-${i}`,
    vehicle_id: "vehicle-2",
    kind,
    verified: i < 3,
    expires_on: "2027-10-01",
    storage_path: "demo/no-real-document",
    created_at: ago(1),
  })),
  routes: [
    {
      id: "route-1",
      name_ar: "السموع — الخليل",
      name_en: "As Samu — Hebron",
      governorate: "الخليل",
      active: true,
    },
    {
      id: "route-2",
      name_ar: "السموع — دورا",
      name_en: "As Samu — Dura",
      governorate: "الخليل",
      active: true,
    },
  ],
  stops: [
    {
      id: "stop-1",
      route_id: "route-1",
      name_ar: "موقف الولي",
      name_en: "Al Wali station",
      sequence: 0,
      latitude: 31.4,
      longitude: 35.07,
    },
    {
      id: "stop-2",
      route_id: "route-1",
      name_ar: "موقف الخليل",
      name_en: "Hebron station",
      sequence: 1,
      latitude: 31.53,
      longitude: 35.09,
    },
  ],
  trips: [
    {
      id: "trip-1",
      vehicle_id: "vehicle-1",
      origin: "السموع",
      destination: "الخليل",
      service: "shared",
      state: "active",
      price: 15,
      seat_limit: 7,
      street_passengers: 2,
      starts_at: ago(-1),
      ends_at: ago(-2),
      created_at: ago(2),
    },
    {
      id: "trip-2",
      vehicle_id: "vehicle-1",
      origin: "السموع",
      destination: "دورا",
      service: "shared",
      state: "published",
      price: 12,
      seat_limit: 7,
      street_passengers: 0,
      starts_at: ago(-24),
      ends_at: ago(-25),
      created_at: ago(3),
    },
  ],
  bookings: [
    {
      id: "booking-1",
      trip_id: "trip-1",
      service: "shared",
      rider_id: "rider-1",
      state: "confirmed",
      seats: 1,
      total_price: 15,
      created_at: ago(0.2),
    },
    {
      id: "booking-2",
      trip_id: "trip-1",
      rider_id: "rider-2",
      state: "boarded",
      seats: 2,
      total_price: 30,
      created_at: ago(0.8),
    },
  ],
  ride_requests: [
    {
      id: "request-1",
      rider_id: "rider-1",
      origin: "السموع",
      destination: "رام الله",
      mode: "posted",
      service: "shared",
      seats: 2,
      state: "searching",
      requested_at: ago(-24),
      created_at: ago(1),
    },
  ],
  offers: [],
  vehicle_locations: [
    {
      vehicle_id: "vehicle-1",
      latitude: 31.48,
      longitude: 35.08,
      updated_at: ago(0.01),
    },
  ],
  violations: [
    {
      id: "violation-1",
      user_id: "rider-1",
      booking_id: "old-booking",
      kind: "late_cancel",
      voided: false,
      created_at: ago(24),
    },
  ],
  appeals: [
    {
      id: "appeal-1",
      violation_id: "violation-1",
      user_id: "rider-1",
      message: "تغير موعد الرحلة ولم أستطع الوصول. أرجو مراجعة الحالة.",
      state: "pending",
      created_at: ago(1),
    },
  ],
  notifications: [
    {
      id: "demo-driver-cancellation-review",
      user_id: "demo-owner",
      kind: "driver.cancellation_review",
      body: JSON.stringify({
        driver_id: "driver-1",
        full_name: "محمد الحوامدة",
        count: 3,
        window_days: 30,
        vehicle_id: null,
      }),
      created_at: ago(0.1),
    },
    {
      id: "notice-1",
      user_id: "rider-1",
      kind: "booking.confirmed",
      body: "تم تأكيد حجزك",
      created_at: ago(0.2),
    },
  ],
  audit_log: [
    {
      id: "audit-1",
      action: "booking.accept",
      actor_id: "driver-1",
      entity_id: "booking-1",
      created_at: ago(0.2),
    },
    {
      id: "audit-2",
      action: "trip.publish",
      actor_id: "driver-1",
      entity_id: "trip-2",
      created_at: ago(3),
    },
  ],
  settings: [
    {
      key: "policy",
      value: {
        late_cancel_minutes: 60,
        no_show_minutes: 5,
        violation_limit: 3,
        window_days: 30,
        suspension_days: 7,
      },
    },
  ],
};
export async function fetchRows(
  table: Table,
  page: number,
  search: string,
  filters: Record<string, string | boolean> = {},
  sort: string = "newest",
): Promise<{ rows: Row[]; count: number }> {
  if (!supabase) throw new Error("SUPABASE_NOT_CONFIGURED");
  const { data: pageData, error: pageError } = await supabase.rpc(
    Object.keys(filters).length || sort !== "newest"
      ? "admin_page_filtered"
      : "admin_page",
    Object.keys(filters).length || sort !== "newest"
      ? { tbl: table, query: search, page, filters, sort }
      : { tbl: table, query: search, page },
  );
  if (pageError) throw pageError;
  return pageData as { rows: Row[]; count: number };
}
export async function adminAction(action: string, p: Row) {
  if (!navigator.onLine) throw new Error("OFFLINE");
  if (!supabase) throw new Error("SUPABASE_NOT_CONFIGURED");
  const { data, error } = await supabase.rpc("admin_action", { a: action, p });
  if (error) throw error;
  return data;
}
