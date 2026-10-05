export function errorMessage(e: unknown, en: boolean) {
  const message =
    e instanceof Error
      ? e.message
      : String((e as { message?: string })?.message ?? e);
  const known: Record<string, [string, string]> = {
    admin_page_filtered: ['الفلاتر المتقدمة غير متاحة حاليًا. يمكنك استخدام البحث حتى اكتمال التحديث.', 'Advanced filters are not available yet. Search remains available while the update is completed.'],
    INVALID_ADMIN_FILTER: ['الفلاتر غير صالحة لهذا القسم.','These filters are not valid for this section.'],
    INVALID_ADMIN_DATE: ['راجع التواريخ؛ تاريخ البداية يجب أن يسبق النهاية.','Check dates: the start must precede the end.'],
    INVALID_ADMIN_SORT: ['اختر ترتيبًا متاحًا لهذا القسم.','Choose an available sort for this section.'],
    APPLICATION_NOT_SUBMITTED: [
      "طلب السائق ما زال مسودة. يجب إرساله مكتملًا قبل الاعتماد.",
      "The driver application is still a draft. Submit it before approval.",
    ],
    ADMIN_MFA_REQUIRED: [
      "يلزم حساب إدارة مع مصادقة ثنائية.",
      "An admin account with MFA is required.",
    ],
    DOCUMENTS_INCOMPLETE: [
      "راجع واعتمد كل الوثائق المطلوبة أولًا.",
      "Verify all required documents first.",
    ],
    DRIVER_IDENTITY_REQUIRED: [
      "يلزم استكمال اسم السائق وتاريخ ميلاده ورقم هاتفه قبل الاعتماد.",
      "Complete the driver's full name, date of birth and phone before approval.",
    ],
    PERMIT_ROUTE_REQUIRED: [
      "أضف خط البيرميت المعتمد للسيارة أولًا.",
      "Assign an approved permit route first.",
    ],
    "Invalid login credentials": [
      "البريد أو كلمة المرور غير صحيحة.",
      "The email or password is incorrect.",
    ],
    "Email not confirmed": [
      "أكد بريدك الإلكتروني قبل الدخول.",
      "Confirm your email before signing in.",
    ],
    VEHICLE_ALREADY_ON_TRIP: [
      "أنهِ رحلة السيارة الحالية أولًا.",
      "Finish the vehicle's current trip first.",
    ],
    PASSENGERS_REMAIN: [
      "يوجد ركاب على متن السيارة.",
      "There are still passengers on board.",
    ],
    PERMIT_ROUTE_MISMATCH: [
      "هذه الرحلة خارج الخط المعتمد.",
      "This journey is outside the approved route.",
    ],
    "Invalid TOTP code": [
      "رمز التحقق غير صحيح أو انتهت صلاحيته. أدخل الرمز الحالي من تطبيق المصادقة.",
      "The code is incorrect or expired. Enter the current code from your authenticator.",
    ],
    "Invalid MFA verification code": [
      "رمز التحقق غير صحيح أو انتهت صلاحيته. أدخل الرمز الحالي من تطبيق المصادقة.",
      "The code is incorrect or expired. Enter the current code from your authenticator.",
    ],
    OFFLINE: ["لا يمكن الحفظ دون اتصال.", "Cannot save while offline."],
    POLICY_REQUIRES_MIGRATION: [
      "تغيير سياسة الحظر يحتاج تحديثًا منظمًا لقواعد الخادم.",
      "Policy changes require a server migration.",
    ],
    OWNER_REQUIRED: [
      "هذه العملية تحتاج صلاحية المالك.",
      "Owner permission is required.",
    ],
  };
  return (
    Object.entries(known).find(([key]) => message.includes(key))?.[1][
      en ? 1 : 0
    ] ?? message
  );
}

