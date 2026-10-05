import { useEffect, useState, type FormEvent } from "react";
import { X } from "lucide-react";
import { supabase, type Row } from "../data";
import { translate } from "../translations";
import { fromPalestineInput, toPalestineInput } from "../time";
import { localLabel } from "../core/labels";
import { parseAdminNumber } from "../core/input_normalization";
import type { Action } from "../core/action_types";
export function ActionForm({
  action,
  row,
  en,
  onClose,
  onSubmit,
  busy,
  error,
  routes,
}: {
  action: Action;
  row: Row | null;
  en: boolean;
  onClose: () => void;
  onSubmit: (v: Row) => Promise<void>;
  busy: boolean;
  error: string;
  routes?: Row[];
}) {
  const [options, setOptions] = useState<Row[]>(routes ?? []);
  const [validationError, setValidationError] = useState("");
  useEffect(() => {
    if (!routes && action.fields?.includes("route_id") && supabase)
      supabase
        .from("routes")
        .select("*")
        .eq("active", true)
        .then(({ data }) => setOptions(data ?? []));
  }, [action, routes]);
  const submit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setValidationError("");
    const form = new FormData(e.currentTarget);
    const p: Row = {};
    for (const key of action.fields ?? []) {
      let val: unknown = form.get(key);
      if (["capacity", "sequence", "latitude", "longitude"].includes(key)) {
        try {
          val = parseAdminNumber(key, val);
        } catch {
          setValidationError(
            en
              ? "Enter a valid value for " + translate(key, en)
              : "أدخل قيمة صحيحة في " + translate(key, en),
          );
          return;
        }
      }
      if (key === "active") val = val === "true";
      if (key === "value" || key === "path_geojson") {
        try {
          val = String(val).trim() ? JSON.parse(String(val)) : null;
        } catch {
          setValidationError(
            en ? "Enter valid JSON" : "أدخل بيانات مسار صحيحة بصيغة JSON",
          );
          return;
        }
      }
      if (["until", "starts_at", "ends_at"].includes(key))
        val = fromPalestineInput(String(val));
      p[key] = val;
    }
    void onSubmit(p);
  };
  return (
    <div className="modal-backdrop">
      <form className="action-modal" onSubmit={submit}>
        <div className="panel-heading">
          <h2>{localLabel(action.label, en)}</h2>
          <button
            type="button"
            className="icon-button"
            onClick={onClose}
            aria-label={en ? "Close" : "إغلاق"}
          >
            <X />
          </button>
        </div>
        <p className="muted">
          {en
            ? "Review the change. This action is recorded in the audit log."
            : "راجع التغيير قبل حفظه. العملية ستُسجل في سجل التدقيق."}
        </p>
        {(action.fields ?? []).map((key) => (
          <label className="form-field" key={key}>
            <span>{translate(key, en)}</span>
            {key === "role" ? (
              <select name={key} defaultValue={String(row?.role ?? "operator")}>
                {["rider", "driver", "operator"].map((r) => (
                  <option key={r} value={r}>
                    {translate(r, en)}
                  </option>
                ))}
              </select>
            ) : key === "route_id" ? (
              <select name={key} required>
                <option value="">
                  {en ? "Choose an approved route" : "اختر خطًا معتمدًا"}
                </option>
                {options.map((r) => (
                  <option value={String(r.id)} key={String(r.id)}>
                    {String(r[en ? "name_en" : "name_ar"])}
                  </option>
                ))}
              </select>
            ) : key === "active" ? (
              <select name={key} defaultValue={String(row?.active ?? true)}>
                <option value="true">{en ? "Active" : "مفعّل"}</option>
                <option value="false">{en ? "Inactive" : "متوقف"}</option>
              </select>
            ) : [
                "value",
                "body",
                "resolution",
                "note",
                "reason",
                "path_geojson",
              ].includes(key) ? (
              <textarea
                name={key}
                defaultValue={
                  typeof row?.[key] === "object"
                    ? JSON.stringify(row[key], null, 2)
                    : String(row?.[key] ?? "")
                }
                required={!["note", "reason", "path_geojson"].includes(key)}
                maxLength={key === "path_geojson" ? 100000 : 2000}
              />
            ) : (
              <input
                name={key}
                required
                defaultValue={
                  ["until", "starts_at", "ends_at"].includes(key) && row?.[key]
                    ? toPalestineInput(String(row[key]))
                    : String(row?.[key] ?? "")
                }
                type={
                  ["until", "starts_at", "ends_at"].includes(key)
                    ? "datetime-local"
                    : "text"
                }
                inputMode={
                  ["capacity", "sequence"].includes(key)
                    ? "numeric"
                    : ["latitude", "longitude"].includes(key)
                      ? "decimal"
                      : undefined
                }
                dir={
                  ["capacity", "sequence", "latitude", "longitude"].includes(
                    key,
                  )
                    ? "ltr"
                    : undefined
                }
              />
            )}
          </label>
        ))}
        {(error || validationError) && (
          <div className="error-banner">{error || validationError}</div>
        )}
        {action.fields?.some((key) =>
          ["until", "starts_at", "ends_at"].includes(key),
        ) && (
          <p className="muted">
            {en ? "Dates use Palestine time." : "المواعيد بتوقيت فلسطين."}
          </p>
        )}
        {action.fields?.includes("path_geojson") && (
          <p className="muted">
            {en
              ? "The road path must follow the approved stops."
              : "يجب أن يتبع مسار الطريق ترتيب المحطات المعتمدة."}
          </p>
        )}
        <div className="modal-footer">
          <button type="button" className="secondary" onClick={onClose}>
            {en ? "Back" : "رجوع"}
          </button>
          <button className="primary" disabled={busy}>
            {busy
              ? en
                ? "Saving…"
                : "جارٍ الحفظ…"
              : en
                ? "Confirm & save"
                : "تأكيد وحفظ"}
          </button>
        </div>
      </form>
    </div>
  );
}
