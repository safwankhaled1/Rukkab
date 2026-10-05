export function driverNoticeTitle(kind: string, en: boolean): string {
  const titles: Record<string, [string, string]> = {
    "driver.application_submitted": [
      "طلب سائق مكتمل للمراجعة",
      "Completed driver application",
    ],
    "driver.application_received": [
      "تم استلام طلب السائق",
      "Driver application received",
    ],
    "driver.cancellation_review": [
      "إلغاءات مؤثرة متكررة للمراجعة",
      "Repeated cancellations need review",
    ],
  };
  return (
    titles[kind]?.[en ? 1 : 0] ??
    (en
      ? "Earlier registration before submission"
      : "تسجيل سابق قبل إكمال الطلب")
  );
}

export function driverNoticeMessage(
  kind: string,
  body: string,
  en: boolean,
): string {
  const title = driverNoticeTitle(kind, en);
  try {
    const notice = JSON.parse(body);
    const name =
      typeof notice.full_name === "string"
        ? notice.full_name
        : typeof notice.plate === "string"
          ? notice.plate
          : "";
    if (
      kind === "driver.cancellation_review" &&
      Number.isSafeInteger(notice.count) &&
      notice.count > 0 &&
      Number.isSafeInteger(notice.window_days) &&
      notice.window_days > 0
    ) {
      return en
        ? `${title}: ${name} · ${notice.count} cancellations in ${notice.window_days} days. Review the record before taking action.`
        : `${title}: ${name} · ${notice.count} إلغاءات خلال ${notice.window_days} يومًا. راجع السجل قبل اتخاذ إجراء.`;
    }
    return name ? `${title}: ${name}` : title;
  } catch {
    return title;
  }
}
