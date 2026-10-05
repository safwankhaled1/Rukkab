export function documentMessage(
  kind: string,
  body: string,
  en: boolean,
): string {
  try {
    const data = JSON.parse(body);
    const names: Record<string, [string, string]> = {
      license: ["رخصة القيادة", "Driving license"],
      permit: ["البيرميت", "Permit"],
      insurance: ["التأمين", "Insurance"],
      registration: ["ترخيص السيارة", "Vehicle registration"],
    };
    const detail = `${names[data.document_kind]?.[en ? 1 : 0] ?? (en ? "Document" : "الوثيقة")} · ${data.plate ?? ""} · ${data.expires_on ?? ""}`;
    return kind === "document.renewal"
      ? en
        ? `${detail}: renew before expiry (${data.days_remaining} days remaining).`
        : `${detail}: جدد قبل الانتهاء (متبقي ${data.days_remaining} يوم).`
      : en
        ? `${detail}: expired. New driver work is paused until renewal and approval.`
        : `${detail}: انتهت الصلاحية. العمل الجديد متوقف لحين التجديد والاعتماد.`;
  } catch {
    return en ? "Review your vehicle documents." : "راجع وثائق السيارة.";
  }
}
