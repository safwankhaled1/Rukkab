import { useEffect, useState } from "react";
import { BrandMark } from "./components/BrandMark";
import { RecordFilters } from "./components/RecordFilters";
import {
  filterDemoRows,
  recordsCsv,
  type RecordFilters as FilterValues,
  type RecordSort,
} from "./core/record_filters";
import type { Session } from "@supabase/supabase-js";
import {
  Activity,
  ArrowUpRight,
  Bell,
  Bus,
  CalendarDays,
  Check,
  ChevronLeft,
  ChevronRight,
  CircleHelp,
  ClipboardCheck,
  FileCheck2,
  Globe2,
  LayoutDashboard,
  LogOut,
  MapPin,
  Menu,
  MoreHorizontal,
  RefreshCw,
  Route,
  Search,
  Settings,
  ShieldCheck,
  Ticket,
  Users,
  X,
} from "lucide-react";
import {
  adminAction,
  demoData,
  demoDefault,
  fetchRows,
  supabase,
  type Row,
  type Table,
} from "./data";
import { columns, translate } from "./translations";
import { WeeklyChart } from "./components/BookingChart";
import { ActionForm } from "./components/RecordActionForm";
import { Login, Mfa, PasswordRecovery } from "./components/AdminAuthentication";
import { errorMessage } from "./core/errors";
import { documentMessage } from "../../../supabase/functions/send-notifications/document-messages";
import {
  driverNoticeMessage,
  driverNoticeTitle,
} from "../../../supabase/functions/send-notifications/driver-messages";
import { localLabel } from "./core/labels";
import type { Action } from "./core/action_types";

type Section = Table | "dashboard";
const navigation: [Section, typeof Users][] = [
  ["dashboard", LayoutDashboard],
  ["profiles", Users],
  ["vehicles", Bus],
  ["documents", FileCheck2],
  ["routes", Route],
  ["stops", MapPin],
  ["trips", CalendarDays],
  ["bookings", Ticket],
  ["ride_requests", Search],
  ["offers", ClipboardCheck],
  ["vehicle_locations", Activity],
  ["violations", ShieldCheck],
  ["appeals", CircleHelp],
  ["notifications", Bell],
  ["audit_log", ClipboardCheck],
  ["settings", Settings],
];
const actions: Partial<Record<Table, Action[]>> = {
  profiles: [
    {
      label: "تعليق الحساب|Suspend account",
      action: "suspend_user",
      fields: ["until", "note"],
    },
    { label: "رفع التعليق|Restore account", action: "restore_user" },
    {
      label: "تعطيل الحساب|Disable account",
      action: "disable_user",
      fixed: { disabled: true },
    },
    {
      label: "تفعيل الحساب|Enable account",
      action: "disable_user",
      fixed: { disabled: false },
    },
    {
      label: "تغيير الصلاحية|Change role",
      action: "set_role",
      fields: ["role"],
    },
    {
      label: "إرسال إشعار|Send notification",
      action: "notify_user",
      fields: ["body"],
    },
  ],
  vehicles: [
    {
      label: "اعتماد السيارة|Approve vehicle",
      action: "approve_vehicle",
      fields: ["capacity", "note"],
    },
    {
      label: "إيقاف الاعتماد|Revoke approval",
      action: "reject_vehicle",
      fields: ["note"],
    },
    {
      label: "إضافة خط بيرميت|Assign permit route",
      action: "assign_route",
      fields: ["route_id"],
    },
    {
      label: "إزالة خط|Remove route",
      action: "remove_route",
      fields: ["route_id"],
    },
  ],
  documents: [
    {
      label: "اعتماد الوثيقة|Verify document",
      action: "verify_document",
      fixed: { verified: true },
    },
    {
      label: "إلغاء اعتماد الوثيقة|Unverify document",
      action: "verify_document",
      fixed: { verified: false },
    },
  ],
  routes: [
    {
      label: "تعديل الخط|Edit route",
      action: "save_route",
      fields: ["name_ar", "name_en", "governorate", "active", "path_geojson"],
    },
  ],
  stops: [
    {
      label: "تعديل المحطة|Edit stop",
      action: "save_stop",
      fields: ["name_ar", "name_en", "latitude", "longitude"],
    },
  ],
  trips: [
    { label: "إلغاء الرحلة|Cancel trip", action: "cancel", rpc: "trip_action" },
    {
      label: "تغيير الموعد|Reschedule trip",
      action: "reschedule",
      rpc: "trip_action",
      fields: ["starts_at", "ends_at"],
    },
  ],
  bookings: [
    {
      label: "إلغاء الحجز|Cancel booking",
      action: "cancel",
      rpc: "booking_action",
      fields: ["reason"],
    },
  ],
  appeals: [
    {
      label: "قبول الاعتراض|Accept appeal",
      action: "resolve_appeal",
      fields: ["resolution"],
      fixed: { accepted: true },
    },
    {
      label: "رفض الاعتراض|Reject appeal",
      action: "resolve_appeal",
      fields: ["resolution"],
      fixed: { accepted: false },
    },
  ],
  settings: [
    {
      label: "تعديل الإعداد|Edit setting",
      action: "save_setting",
      fields: ["key", "value"],
    },
  ],
};
const currency = (n: unknown) => `₪ ${Number(n ?? 0).toLocaleString()}`;

export function App() {
  const [en, setEn] = useState(false),
    [demo, setDemo] = useState(demoDefault),
    [session, setSession] = useState<Session | null>(null),
    [authorized, setAuthorized] = useState(false),
    [profile, setProfile] = useState<Row | null>(null),
    [recovering, setRecovering] = useState(false);
  const [section, setSection] = useState<Section>("dashboard"),
    [mobileMenu, setMobileMenu] = useState(false),
    [page, setPage] = useState(0),
    [search, setSearch] = useState(""),
    [rows, setRows] = useState<Row[]>([]),
    [count, setCount] = useState(0),
    [loading, setLoading] = useState(false),
    [revision, setRevision] = useState(0);
  const [selected, setSelected] = useState<Row | null>(null),
    [action, setAction] = useState<Action | null>(null),
    [error, setError] = useState(""),
    [toast, setToast] = useState(""),
    [online, setOnline] = useState(navigator.onLine),
    [lastUpdated, setLastUpdated] = useState<Date | null>(null),
    [stats, setStats] = useState<Row>({}),
    [demoRows, setDemoRows] = useState(() => structuredClone(demoData));
  const [filters, setFilters] = useState<FilterValues>({});
  const [sort, setSort] = useState<RecordSort>("newest");
  const [dense, setDense] = useState(false);
  const [unreadNotices, setUnreadNotices] = useState<number | null>(null);
  const t = (key: string) => translate(key, en);
  const text = (ar: string, english: string) => (en ? english : ar);
  useEffect(() => {
    document.documentElement.dir = en ? "ltr" : "rtl";
    document.documentElement.lang = en ? "en" : "ar";
  }, [en]);
  useEffect(() => {
    if (!supabase) return;
    let active = true;
    let revision = 0;
    async function syncSession(event?: string, next?: Session | null) {
      const request = ++revision;
      const { data, error } = await supabase!.auth.getSession();
      if (!active || request !== revision) return;
      setSession(error ? null : data.session);
      if (!data.session || error) {
        setProfile(null);
        setAuthorized(false);
      }
      if (
        event === "PASSWORD_RECOVERY" &&
        data.session?.access_token === next?.access_token &&
        data.session
      )
        setRecovering(true);
    }
    void syncSession();
    const { data } = supabase.auth.onAuthStateChange((event, next) => {
      // A broadcast may belong to another tab. Read this tab's actual session;
      // never run awaited auth calls while inside the SDK notification callback.
      queueMicrotask(() => {
        if (active) void syncSession(event, next);
      });
    });
    return () => {
      active = false;
      data.subscription.unsubscribe();
    };
  }, []);
  useEffect(() => {
    let alive = true;
    setAuthorized(false);
    if (!session || !supabase) return;
    Promise.all([
      supabase.from("profiles").select("*").eq("id", session.user.id).single(),
      supabase.auth.mfa.getAuthenticatorAssuranceLevel(),
    ]).then(([p, level]) => {
      if (!alive) return;
      setProfile(p.data);
      setAuthorized(
        ["owner", "operator"].includes(p.data?.role) &&
          !p.data?.disabled &&
          level.data?.currentLevel === "aal2",
      );
    });
    return () => {
      alive = false;
    };
  }, [session]);
  useEffect(() => {
    const update = () => {
      setOnline(navigator.onLine);
      if (navigator.onLine) setRevision((v) => v + 1);
    };
    window.addEventListener("online", update);
    window.addEventListener("offline", update);
    return () => {
      window.removeEventListener("online", update);
      window.removeEventListener("offline", update);
    };
  }, []);
  useEffect(() => {
    setPage(0);
    setSelected(null);
    setError("");
  }, [section, search, filters, sort]);
  useEffect(() => {
    let alive = true;
    if (!demo && !authorized) return;
    const load = async () => {
      setLoading(true);
      try {
        if (section === "dashboard") {
          if (demo) {
            setStats({
              riders: demoRows.profiles.filter((x) => x.role === "rider")
                .length,
              drivers: demoRows.profiles.filter((x) => x.role === "driver")
                .length,
              active_trips: demoRows.trips.filter((x) => x.state === "active")
                .length,
              today_bookings: demoRows.bookings.length,
              pending_vehicles: demoRows.vehicles.filter((x) => !x.approved)
                .length,
              pending_appeals: demoRows.appeals.filter(
                (x) => x.state === "pending",
              ).length,
              expired_documents: 0,
              week: [2, 4, 3, 7, 5, 9, 2].map((count, i) => ({
                date: new Date(Date.now() - (6 - i) * 86400000).toISOString(),
                count,
              })),
            });
            setRows(demoRows.bookings);
          } else {
            const { data, error } = await supabase!.rpc("admin_overview");
            if (error) throw error;
            const recent = await fetchRows("bookings", 0, "");
            if (alive) {
              setStats(data);
              setRows(recent.rows);
            }
          }
        } else if (demo) {
          const list = filterDemoRows(
            demoRows[section],
            search,
            filters,
            sort,
            section,
          );
          setRows(list.slice(page * 20, page * 20 + 20));
          setCount(list.length);
        } else {
          const result = await fetchRows(section, page, search, filters, sort);
          if (alive) {
            setRows(result.rows);
            setCount(result.count);
          }
        }
        if (alive) {
          setLastUpdated(new Date());
          setError("");
        }
      } catch (e) {
        if (alive) setError(errorMessage(e, en));
      } finally {
        if (alive) setLoading(false);
      }
    };
    const timer = setTimeout(load, 250);
    return () => {
      alive = false;
      clearTimeout(timer);
    };
  }, [
    section,
    page,
    search,
    revision,
    demo,
    authorized,
    demoRows,
    en,
    filters,
    sort,
  ]);
  useEffect(() => {
    if (demo || !authorized || !supabase) return;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const channel = supabase
      .channel("admin-events")
      .on("postgres_changes", { event: "*", schema: "public" }, (event) => {
        if (event.table === "notifications" && event.eventType === "INSERT") {
          const notice = event.new;
          if (
            notice.user_id === session?.user.id &&
            String(notice.kind).startsWith("driver.")
          ) {
            setToast(
              notice.kind === "driver.cancellation_review"
                ? text(
                    "إلغاءات متكررة — افتح الإشعارات لمراجعة السائق",
                    "Repeated cancellations — open notifications to review the driver",
                  )
                : text(
                    "طلب سائق جديد — افتح الإشعارات لمراجعة بياناته",
                    "New driver submission — open notifications to review",
                  ),
            );
          }
        }
        clearTimeout(timer);
        timer = setTimeout(() => setRevision((v) => v + 1), 500);
      })
      .subscribe();
    return () => {
      clearTimeout(timer);
      void supabase!.removeChannel(channel);
    };
  }, [demo, authorized, session?.user.id, en]);
  useEffect(() => {
    let alive = true;
    setUnreadNotices(null);
    if (!demo && authorized && supabase && session?.user.id) {
      void supabase
        .from("notifications")
        .select("id", { count: "exact", head: true })
        .eq("user_id", session.user.id)
        .is("read_at", null)
        .then(({ count: total, error: failure }) => {
          if (alive && !failure) setUnreadNotices(total);
        });
    }
    return () => {
      alive = false;
    };
  }, [demo, authorized, session?.user.id, revision]);
  useEffect(() => {
    if (toast) {
      const timer = setTimeout(() => setToast(""), 5000);
      return () => clearTimeout(timer);
    }
  }, [toast]);
  const format = (key: string, value: unknown, record?: Row) => {
    if (key === "kind" && String(value).startsWith("driver."))
      return driverNoticeTitle(String(value), en);
    if (key === "body" && String(record?.kind ?? "").startsWith("driver."))
      return driverNoticeMessage(String(record?.kind), String(value ?? ""), en);
    if (key === "body" && String(record?.kind ?? "").startsWith("document.")) {
      return documentMessage(String(record?.kind), String(value ?? ""), en);
    }
    if (record?.[`${key}_label`]) return String(record[`${key}_label`]);
    if (value === null || value === undefined) return "—";
    if (typeof value === "boolean")
      return value ? text("نعم", "Yes") : text("لا", "No");
    if (typeof value === "object") return JSON.stringify(value);
    if (/price/.test(key)) return currency(value);
    if (/(_at|_on|until)$/.test(key)) {
      const d = new Date(String(value));
      return isNaN(d.getTime())
        ? String(value)
        : d.toLocaleString(en ? "en-GB" : "ar-PS", {
            timeZone: "Asia/Hebron",
            dateStyle: "medium",
            ...(key.endsWith("_on") ? {} : { timeStyle: "short" }),
          });
    }
    if (key.endsWith("_id") || key === "id") {
      if (demo) {
        const lookup = [
          ...demoRows.profiles,
          ...demoRows.vehicles,
          ...demoRows.routes,
          ...demoRows.trips,
        ].find((x) => x.id === value);
        if (lookup)
          return String(
            lookup.full_name ??
              lookup.plate ??
              lookup.name_ar ??
              `${lookup.origin} ← ${lookup.destination}`,
          );
      }
      return String(value).slice(0, 8);
    }
    return t(String(value));
  };
  const switchSection = (s: Section) => {
    setFilters({});
    setSort("newest");
    // Do not render records from the old resource under the new columns.
    setRows([]);
    setCount(0);
    setLoading(true);
    setSelected(null);
    setAction(null);
    setPage(0);
    setSection(s);
    setMobileMenu(false);
    setSearch("");
  };
  const execute = async (values: Row) => {
    if (!action) return;
    setError("");
    setLoading(true);
    try {
      const p: Row = { id: selected?.id, ...values, ...action.fixed };
      if (section === "vehicles") p.vehicle_id = selected?.id;
      if (demo) {
        setDemoRows((prev) => {
          const next = structuredClone(prev);
          const table = section === "dashboard" ? "bookings" : section;
          const row = next[table].find((x) =>
            selected?.id
              ? x.id === selected.id
              : selected?.key
                ? x.key === selected.key
                : false,
          );
          if (row) {
            if (action.action === "approve_vehicle") {
              row.approved = true;
              row.capacity = Number(p.capacity);
            } else if (action.action === "reject_vehicle") row.approved = false;
            else if (action.action === "verify_document")
              row.verified = p.verified;
            else if (action.action === "resolve_appeal") {
              row.state = p.accepted ? "accepted" : "rejected";
              row.resolution = p.resolution;
            } else if (action.action === "disable_user")
              row.disabled = p.disabled;
            else if (action.action === "suspend_user")
              row.suspended_until = p.until;
            else if (action.action === "restore_user")
              row.suspended_until = null;
            else if (action.action === "set_role") row.role = p.role;
            else if (action.action === "cancel") row.state = "cancelled";
            else Object.assign(row, values);
          } else if (
            action.action === "save_route" ||
            action.action === "save_stop"
          )
            next[table].push({
              ...values,
              id: crypto.randomUUID(),
              created_at: new Date().toISOString(),
            });
          next.audit_log.unshift({
            id: crypto.randomUUID(),
            actor_id: "demo-owner",
            action: `admin.${action.action}`,
            created_at: new Date().toISOString(),
          });
          return next;
        });
        setToast(
          text("تم تعديل البيانات التجريبية فقط", "Demo data updated only"),
        );
      } else if (action.rpc) {
        const args =
          action.rpc === "trip_action"
            ? { tid: selected?.id, a: action.action, p: values }
            : {
                bid: selected?.id,
                a: action.action,
                reason: values.reason ?? "admin_action",
              };
        if (!online) throw new Error("OFFLINE");
        const { error } = await supabase!.rpc(action.rpc, args);
        if (error) throw error;
      } else await adminAction(action.action, p);
      if (!demo)
        setToast(text("تم حفظ التغيير وتسجيله", "Change saved and audited"));
      setAction(null);
      setSelected(null);
      setRevision((v) => v + 1);
    } catch (e) {
      setError(errorMessage(e, en));
    } finally {
      setLoading(false);
    }
  };
  if (recovering)
    return <PasswordRecovery en={en} onDone={() => setRecovering(false)} />;
  if (!demo && !session)
    return (
      <Login
        en={en}
        onLanguage={() => setEn(!en)}
        onDemo={() => setDemo(true)}
      />
    );
  if (!demo && !authorized) {
    if (profile && !["owner", "operator"].includes(String(profile.role)))
      return (
        <div className="gate">
          <ShieldCheck size={40} />
          <h1>
            {text(
              "هذا الحساب لا يمتلك صلاحية الإدارة",
              "This account has no admin access",
            )}
          </h1>
          <button onClick={() => supabase!.auth.signOut()}>
            {text("تسجيل الخروج", "Sign out")}
          </button>
        </div>
      );
    return <Mfa en={en} />;
  }
  const actualSection = section === "dashboard" ? "bookings" : section;
  const newAction =
    section === "routes"
      ? {
          label: "إضافة خط|Add route",
          action: "save_route",
          fields: ["name_ar", "name_en", "governorate", "path_geojson"],
        }
      : section === "stops"
        ? {
            label: "إضافة محطة|Add stop",
            action: "save_stop",
            fields: [
              "route_id",
              "name_ar",
              "name_en",
              "sequence",
              "latitude",
              "longitude",
            ],
          }
        : null;
  return (
    <div className="app-shell">
      <aside className={`sidebar ${mobileMenu ? "open" : ""}`}>
        <a
          className="brand"
          href="#"
          onClick={(e) => {
            e.preventDefault();
            switchSection("dashboard");
          }}
        >
          <BrandMark size={48} />
          <span>
            ركاب<small>RUKKAB</small>
          </span>
        </a>
        <div className="workspace-label">
          {text("مركز إدارة العمليات", "OPERATIONS CENTER")}
        </div>
        <nav>
          {navigation.map(([key, Icon], i) => (
            <button
              key={key}
              className={`${section === key ? "selected" : ""} ${i === 10 ? "nav-divider" : ""}`}
              onClick={() => switchSection(key)}
            >
              <Icon size={19} />
              <span>{t(key)}</span>
              {key === "vehicles" && Number(stats.pending_vehicles) > 0 && (
                <em>{String(stats.pending_vehicles)}</em>
              )}
            </button>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <div className="owner-avatar">{text("ص", "S")}</div>
          <div>
            <strong>
              {demo
                ? text("صفوان · حساب تجريبي", "Safwan · demo")
                : String(profile?.full_name ?? "")}
            </strong>
            <small>
              {demo
                ? text("معاينة صلاحيات المالك", "Owner preview")
                : t(String(profile?.role))}
            </small>
          </div>
          <button
            aria-label="Sign out"
            onClick={() => {
              if (demo) setDemo(false);
              else void supabase!.auth.signOut();
            }}
          >
            <LogOut size={18} />
          </button>
        </div>
      </aside>
      <main className="main-content">
        <header className="topbar">
          <div className="breadcrumbs">
            <button
              className="menu-button"
              aria-label="Menu"
              onClick={() => setMobileMenu(!mobileMenu)}
            >
              <Menu />
            </button>
            <span>{text("مركز الإدارة", "Admin center")}</span>
            <ChevronLeft size={14} />
            <strong>{t(section)}</strong>
          </div>
          <div className="topbar-actions">
            <span className={`connection ${online ? "" : "disconnected"}`}>
              <i />
              {online ? text("متصل", "Online") : text("غير متصل", "Offline")}
            </span>
            <button onClick={() => setEn(!en)}>
              <Globe2 size={17} />
              {en ? "العربية" : "English"}
            </button>
            <button
              aria-label="Notifications"
              onClick={() => switchSection("notifications")}
            >
              <Bell size={20} />
              {unreadNotices !== null && unreadNotices > 0 && (
                <span className="notice-count">
                  {unreadNotices > 99 ? "99+" : unreadNotices}
                </span>
              )}
            </button>
          </div>
        </header>
        {demo && (
          <div className="demo-banner">
            <ShieldCheck size={16} />
            {text(
              "وضع تجريبي — البيانات وهمية والتغييرات محلية فقط. يلزم ربط الخدمات لتشغيل النظام الحقيقي.",
              "Demo mode — sample data and local changes only. Connect services for live operation.",
            )}
          </div>
        )}
        {!online && (
          <div className="error-banner">
            {text(
              "انقطع الاتصال. البيانات المعروضة قديمة؛ التعديلات متوقفة حتى عودة الاتصال.",
              "Offline. Displayed data may be stale; changes are disabled until reconnection.",
            )}
          </div>
        )}
        <div className="page-body">
          <div className="page-heading">
            <div>
              <div className="eyebrow">
                {text(
                  "ركاب / إدارة المواصلات",
                  "RUKKAB / TRANSPORT MANAGEMENT",
                )}
              </div>
              <h1>
                {section === "dashboard"
                  ? text(
                      "كل الرحلات، تحت إدارتك.",
                      "Every ride. In your hands.",
                    )
                  : t(section)}
              </h1>
              <p>
                {section === "dashboard"
                  ? text(
                      "تابع حركة الركاب والسائقين، وخلي الرحلة أسهل للجميع.",
                      "Keep riders and drivers moving. Make every journey easier.",
                    )
                  : text(
                      "إدارة واضحة، وصلاحيات آمنة، وسجل لكل تغيير.",
                      "Clear management, secure permissions, and an audit trail for every change.",
                    )}
              </p>
            </div>
            <button
              className="secondary"
              onClick={() => setRevision((v) => v + 1)}
              disabled={loading}
            >
              <RefreshCw size={16} className={loading ? "spin" : ""} />
              {text("تحديث البيانات", "Refresh data")}
            </button>
          </div>
          {error && (
            <div className="error-banner" role="alert">
              {error}
            </div>
          )}
          {section === "dashboard" && (
            <>
              <div className="stats-grid">
                {[
                  ["riders", Users, "الركاب المسجلون", "Registered riders"],
                  ["drivers", Bus, "السائقون المسجلون", "Registered drivers"],
                  ["active_trips", Route, "رحلات جارية", "Active trips"],
                  ["today_bookings", Ticket, "حجوزات اليوم", "Bookings today"],
                ].map(([key, Icon, ar, english]) => {
                  const I = Icon as typeof Users;
                  return (
                    <article className="stat-card" key={String(key)}>
                      <div className="stat-label">
                        {text(String(ar), String(english))}
                        <span>
                          <I size={20} />
                        </span>
                      </div>
                      <strong>
                        {Number(stats[String(key)] ?? 0).toLocaleString(
                          en ? "en" : "ar",
                        )}
                      </strong>
                      <small>
                        {String(key) === "today_bookings"
                          ? text("حسب توقيت فلسطين", "Palestine time")
                          : text(
                              "من قاعدة البيانات الحالية",
                              "Current database",
                            )}
                      </small>
                    </article>
                  );
                })}
              </div>
              <div className="overview-grid">
                <article className="panel chart-panel">
                  <div className="panel-heading">
                    <div>
                      <h2>{text("حركة الحجوزات", "Booking activity")}</h2>
                      <p>
                        {text(
                          "عدد الحجوزات خلال آخر ٧ أيام",
                          "Bookings over the last 7 days",
                        )}
                      </p>
                    </div>
                    <span className="tag">
                      {text("هذا الأسبوع", "This week")}
                    </span>
                  </div>
                  <WeeklyChart data={(stats.week as Row[]) ?? []} en={en} />
                </article>
                <article className="panel attention-panel">
                  <div className="panel-heading">
                    <h2>{text("بحاجة لمراجعتك", "Needs your attention")}</h2>
                    <span className="attention-dot" />
                  </div>
                  <p>
                    {text(
                      "خطوات بسيطة لضمان رحلات موثوقة.",
                      "A few steps to keep rides reliable.",
                    )}
                  </p>
                  {[
                    [
                      "vehicles",
                      "pending_vehicles",
                      "سيارات بانتظار الاعتماد",
                      "Vehicles awaiting approval",
                    ],
                    [
                      "appeals",
                      "pending_appeals",
                      "اعتراضات جديدة",
                      "New appeals",
                    ],
                    [
                      "documents",
                      "expired_documents",
                      "وثائق منتهية",
                      "Expired documents",
                    ],
                  ].map(([target, key, ar, english]) => (
                    <button
                      className="attention-row"
                      key={key}
                      onClick={() => switchSection(target as Section)}
                    >
                      <div className={`attention-icon ${target}`}>
                        <FileCheck2 size={19} />
                      </div>
                      <span>{text(ar, english)}</span>
                      <strong>{String(stats[key] ?? 0)}</strong>
                      <ArrowUpRight size={16} />
                    </button>
                  ))}
                  <div className="security-note">
                    <ShieldCheck size={18} />
                    <span>
                      {text(
                        "كل تعديل محفوظ في سجل العمليات",
                        "Every change is recorded in the audit log",
                      )}
                    </span>
                  </div>
                </article>
              </div>
            </>
          )}
          <section className="panel table-panel">
            <div className="panel-heading">
              <div>
                <h2>
                  {section === "dashboard"
                    ? text("أحدث الحجوزات", "Latest bookings")
                    : t(section)}
                </h2>
                <p>
                  {section === "dashboard"
                    ? text(
                        "من الطلب إلى الوصول، تابع تفاصيل كل حجز.",
                        "Follow every booking, from request to arrival.",
                      )
                    : text(
                        `${count} سجل · عرض ٢٠ في الصفحة`,
                        `${count} records · 20 per page`,
                      )}
                </p>
              </div>
              {section === "dashboard" ? (
                <button
                  className="text-button"
                  onClick={() => switchSection("bookings")}
                >
                  {text("كل الحجوزات", "All bookings")}
                  <ArrowUpRight size={16} />
                </button>
              ) : newAction ? (
                <button
                  className="primary"
                  onClick={() => {
                    setSelected(null);
                    setAction(newAction);
                  }}
                  disabled={!online}
                >
                  {localLabel(newAction.label, en)} +
                </button>
              ) : null}
            </div>
            {section !== "dashboard" && (
              <div className="table-toolbar">
                <label className="search-box">
                  <Search size={18} />
                  <input
                    placeholder={text("ابحث في السجلات…", "Search records…")}
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                  />
                </label>
                <div className="table-actions">
                  <button
                    className="secondary"
                    aria-pressed={dense}
                    onClick={() => setDense(!dense)}
                  >
                    {text(
                      dense ? "عرض مريح" : "عرض مكثّف",
                      dense ? "Comfortable rows" : "Compact rows",
                    )}
                  </button>
                  <button
                    className="secondary"
                    disabled={loading || rows.length === 0}
                    onClick={() => {
                      const csv = recordsCsv(rows, columns[actualSection], t);
                      const url = URL.createObjectURL(
                        new Blob([csv], { type: "text/csv;charset=utf-8" }),
                      );
                      const link = document.createElement("a");
                      link.href = url;
                      link.download =
                        "rukkab-" +
                        actualSection +
                        "-page-" +
                        (page + 1) +
                        ".csv";
                      link.click();
                      URL.revokeObjectURL(url);
                    }}
                  >
                    {text("تصدير الصفحة CSV", "Export page CSV")}
                  </button>
                </div>
              </div>
            )}
            {section !== "dashboard" && (
              <>
                <RecordFilters
                  table={actualSection}
                  en={en}
                  values={filters}
                  sort={sort}
                  t={t}
                  onApply={(next, order) => {
                    setPage(0);
                    setRows([]);
                    setFilters(next);
                    setSort(order);
                  }}
                />
                <div className="filter-summary">
                  {text(
                    `${Object.keys(filters).length} فلاتر مطبقة · التصدير يشمل الصفحة المعروضة`,
                    `${Object.keys(filters).length} applied filters · export contains the displayed page`,
                  )}
                </div>
              </>
            )}
            <div className={`table-scroll ${dense ? "dense-table" : ""}`}>
              <table>
                <thead>
                  <tr>
                    {columns[actualSection].map((key) => (
                      <th key={key}>{t(key)}</th>
                    ))}
                    <th />
                  </tr>
                </thead>
                <tbody>
                  {rows.map((row, index) => (
                    <tr
                      key={String(row.id ?? row.key ?? row.vehicle_id ?? index)}
                      onClick={() => {
                        setSelected(row);
                        setError("");
                      }}
                      tabIndex={0}
                      onKeyDown={(e) => {
                        if (e.key === "Enter") setSelected(row);
                      }}
                    >
                      {columns[actualSection].map((key) => (
                        <td key={key}>
                          {key === "state" ||
                          key === "application_state" ||
                          key === "approved" ||
                          key === "verified" ? (
                            <span
                              className={`status status-${String(row[key])}`}
                            >
                              {format(key, row[key], row)}
                            </span>
                          ) : (
                            format(key, row[key], row)
                          )}
                        </td>
                      ))}
                      <td>
                        <button className="icon-button" aria-label="Details">
                          <MoreHorizontal size={18} />
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {rows.length === 0 && (
                <div className="empty-state">
                  <Route size={32} />
                  <h3>
                    {loading
                      ? text("جارٍ تحميل البيانات…", "Loading…")
                      : text("لا توجد سجلات هنا بعد", "No records here yet")}
                  </h3>
                  <p>
                    {text(
                      "ستظهر البيانات بعد إضافتها أو تغيير البحث.",
                      "Records appear when added or when the search changes.",
                    )}
                  </p>
                </div>
              )}
            </div>
            <div className="table-footer">
              <span>
                {lastUpdated
                  ? text("آخر تحديث: ", "Last updated: ") +
                    lastUpdated.toLocaleTimeString(en ? "en" : "ar")
                  : ""}
              </span>
              {section !== "dashboard" && (
                <div className="pagination">
                  <button
                    disabled={page === 0}
                    onClick={() => setPage(page - 1)}
                    aria-label="Previous page"
                  >
                    <ChevronRight size={16} />
                  </button>
                  <span>
                    {page + 1} / {Math.max(1, Math.ceil(count / 20))}
                  </span>
                  <button
                    disabled={(page + 1) * 20 >= count}
                    onClick={() => setPage(page + 1)}
                    aria-label="Next page"
                  >
                    <ChevronLeft size={16} />
                  </button>
                </div>
              )}
            </div>
          </section>
          <footer className="page-footer">
            <span>
              © {new Date().getFullYear()}{" "}
              {text("ركاب · الطريق بيجمعنا", "Rukkab · Every road connects us")}
            </span>
            <span>
              <ShieldCheck size={13} />
              {text("إدارة بصلاحيات محمية", "Protected administrative access")}
            </span>
          </footer>
        </div>
      </main>
      {toast && (
        <div className="toast" role="status">
          <Check size={18} />
          {toast}
        </div>
      )}
      {selected && !action && (
        <div className="drawer-backdrop" onClick={() => setSelected(null)}>
          <aside className="detail-drawer" onClick={(e) => e.stopPropagation()}>
            <div className="panel-heading">
              <h2>{text("تفاصيل السجل", "Record details")}</h2>
              <button
                className="icon-button"
                aria-label="Close"
                onClick={() => setSelected(null)}
              >
                <X />
              </button>
            </div>
            <dl>
              {Object.entries(selected).map(([key, value]) => (
                <div key={key}>
                  <dt>{t(key)}</dt>
                  <dd>{format(key, value, selected)}</dd>
                </div>
              ))}
            </dl>
            {actualSection === "notifications" &&
              String(selected.kind).startsWith("driver.") && (
                <button
                  className="primary"
                  onClick={() => {
                    try {
                      const notice = JSON.parse(String(selected.body));
                      if (supabase && selected.user_id === session?.user.id) {
                        void supabase
                          .rpc("account_action", {
                            a: "read_notification",
                            p: { id: selected.id },
                          })
                          .then(({ error: failure }) => {
                            if (!failure) setRevision((v) => v + 1);
                          });
                      }
                      const vehicle = notice.vehicle_id;
                      switchSection(vehicle ? "vehicles" : "profiles");
                      setSearch(String(vehicle ?? notice.driver_id ?? ""));
                      setSelected(null);
                    } catch {
                      setError(
                        text("تعذّر قراءة الإشعار", "Cannot read notification"),
                      );
                    }
                  }}
                >
                  {selected.kind === "driver.cancellation_review"
                    ? text("مراجعة حساب السائق", "Review driver account")
                    : text("مراجعة بيانات السائق", "Review driver submission")}
                </button>
              )}
            {actualSection === "documents" && (
              <button
                className="secondary"
                disabled={demo}
                onClick={async () => {
                  try {
                    const { data, error } = await supabase!.storage
                      .from("driver-documents")
                      .createSignedUrl(String(selected.storage_path), 60);
                    if (error) throw error;
                    window.open(
                      data.signedUrl,
                      "_blank",
                      "noopener,noreferrer",
                    );
                  } catch (e) {
                    setError(errorMessage(e, en));
                  }
                }}
              >
                {text(
                  "عرض الوثيقة · رابط لدقيقة",
                  "View document · 1-minute link",
                )}
              </button>
            )}
            <div className="drawer-actions">
              {(actions[actualSection] ?? []).map((a) => (
                <button
                  className="secondary"
                  key={a.action + JSON.stringify(a.fixed)}
                  disabled={!online}
                  onClick={() => setAction(a)}
                >
                  {localLabel(a.label, en)}
                </button>
              ))}
            </div>
          </aside>
        </div>
      )}
      {action && (
        <ActionForm
          action={action}
          row={selected}
          en={en}
          onClose={() => setAction(null)}
          onSubmit={execute}
          busy={loading}
          error={error}
          routes={demo ? demoRows.routes : undefined}
        />
      )}
    </div>
  );
}
