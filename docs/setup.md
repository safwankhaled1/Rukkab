# تشغيل ركاب وتسليمه لفريق تطوير

## 1. المتطلبات

- Node.js 22 أو أحدث وnpm.
- Flutter stable؛ SDK المستخدم في الفحص محفوظ محليًا في `work/flutter-sdk` ومهمل من Git.
- Android SDK/JDK لإنشاء APK/AAB. جهاز Mac وXcode لإنشاء واختبار نسخة آيفون.
- مشاريع مستقلة للتطوير والتجربة والإنتاج على Supabase. لا تستخدم بيانات ركاب حقيقية للاختبار.

## 2. Supabase

1. أنشئ مشروعًا وحدد منطقة الاستضافة المناسبة وسياسة الاحتفاظ بالبيانات.
2. فعّل تأكيد البريد، كلمة مرور ١٢ حرفًا على الأقل، ومصادقة TOTP. جهّز SMTP فعليًا قبل التسجيل العام.
3. طبّق ملفات `supabase/migrations` بالترتيب باستخدام Supabase CLI (`supabase link` ثم `supabase db push` إلى مشروع التطوير أولًا).
4. تحقق من تفعيل PostGIS وpg_cron، وجود مهمة `rukkab-dispatch`، ودخول جداول Realtime في publication.
5. اضبط روابط إعادة التوجيه لموقع الإدارة الحقيقي و`io.rukkab.app://login-callback` للموبايل. استبدل روابط localhost قبل الإنتاج.
6. سجّل حساب المالك وأكّد بريده. امنحه role=`owner` من SQL Editor بعد التأكد من هويته، أو استخدم `supabase/bootstrap_owner.sql` مع psql. لا توجد كلمة مرور افتراضية أو ترقية تلقائية من الواجهة.
7. سجّل الدخول من لوحة الإدارة وأكمل المصادقة الثنائية. احتفظ بإجراء آمن لاستعادة حساب المالك عند فقدان جهاز المصادقة.

فحص مستندات التخزين: الحاوية `driver-documents` خاصة، لا يمكن تحميل وثيقة مستخدم آخر، والرابط الذي تفتحه الإدارة صالح لمدة ٦٠ ثانية. ملفات الصور/PDF محدودة بـ١٠ ميغابايت. أضف فحص ملفات ضد المحتوى الضار في تجهيز الإنتاج إذا كانت الوثائق ستُفتح خارج المتصفح المعزول.

## 3. لوحة الإدارة

انسخ `apps/admin/.env.example` إلى `apps/admin/.env`، ثم ضع عنوان المشروع ومفتاح publishable/anon العام. **لا تستخدم service_role**.

```powershell
npm ci
npm run dev
npm run build
```

الملفات المنشورة من `apps/admin/dist`. الاستضافة تحتاج HTTPS وعودة مسارات SPA إلى index.html. اضبط Content-Security-Policy بحسب نطاق مشروع Supabase ومصادر الخطوط المستخدمة، وأضف رؤوس منع تضمين لوحة الإدارة داخل iframe. وضع المعاينة التجريبي يظهر بوضوح ولا يمنح صلاحيات حقيقية.

أضف الخطوط والمحطات باللغتين، واعتمد بيانات مواقعها بعد مراجعتها ميدانيًا. لا يُدرج المشروع خطوطًا رسمية أو أجورًا مفترضة. ثم راجع وثائق السائق، أضف خط البيرميت، واعتمد السعة الفعلية للسيارة.

## 4. الموبايل

انسخ `apps/mobile/config.example.json` إلى `apps/mobile/config.json` وضع نفس عنوان Supabase ومفتاحه العام.

```powershell
cd apps/mobile
flutter pub get
flutter run --dart-define-from-file=config.json
flutter build appbundle --dart-define-from-file=config.json
```

على Windows، إذا كانت سياسة الجهاز تسمح بتشغيل سكربتات PowerShell، يمكن تشغيل المحاكي الموجود باستخدام `powershell -File scripts/run-mobile.ps1 -DeviceId emulator-5554` من جذر المشروع. إذا منعت السياسة السكربت استخدم أوامر Flutter المباشرة أعلاه؛ لا يلزم تغيير سياسة الحماية. يكتشف السكربت Flutter المحلي وAndroid SDK وJava المرفق مع Android Studio؛ لا يخزّن كلمات مرور أو مفاتيح خادم. أول بناء يحتاج تنزيل اعتماديات أندرويد. ملف إعداد الموبايل و`.env.local` للإدارة مهملان من Git.

إذا لم تتوفر Supabase CLI عند الإعداد الأول لقاعدة فارغة، يشغّل `node scripts/serve-deployment-review.mjs` صفحة مراجعة محلية على `127.0.0.1:5174` وملف SQL داخل `work/deployment`. الحزمة تنفذ التعديلات بمعاملة واحدة وتمنع التنفيذ فوق مخطط غير فارغ، وتسجل تاريخ التعديلات لتكملة التطوير لاحقًا عبر CLI. أوقف خادم المراجعة بعد الاستخدام.

Android application ID الحالي `io.rukkab.rukkab`؛ راجعه مع الفريق قبل التسجيل في المتاجر. مشروع Android يستخدم توقيع debug المولد حاليًا؛ أنشئ إعداد توقيع release منفصلًا قبل التوزيع ولا ترفع ملفات مفاتيح التوقيع إلى Git.

## 5. دخول الركاب عبر Google وApple

الأزرار تستخدم Supabase OAuth مع callback التطبيق `io.rukkab.app://login-callback`. إعدادات المشروع العامة تُفحص قبل فتح المتصفح؛ عند عدم تفعيل مزود الدخول تظهر رسالة مع إمكانية الدخول بالبريد. الأزرار لا تظهر في تسجيل السائقين، ولا تسمح جلسة OAuth بعمليات حساب السائق.

- Google: أنشئ OAuth Web client في Google Cloud، وأضف `https://hkqookgltexlaoburoya.supabase.co/auth/v1/callback` إلى Authorized redirect URIs. أضف Client ID وClient Secret في Authentication → Sign In / Providers → Google داخل Supabase. احتفظ بالسر على الخادم فقط. راجع [دليل Supabase الرسمي](https://supabase.com/docs/guides/auth/social-login/auth-google).
- Apple: يحتاج إعداد Sign in with Apple في Apple Developer، وService ID ومفتاح توقيع/secret وفق [دليل Supabase الرسمي](https://supabase.com/docs/guides/auth/social-login/auth-apple). يُضاف نفس callback للخدمة؛ أسرار Apple لا تُدرج داخل تطبيق Flutter. تابع مدة صلاحية سر Apple وتجديده؛ مسار OAuth يحتاج عادة تجديده كل ستة أشهر.
- اختبر العودة للتطبيق بعد السماح وبعد الإلغاء، حساب Apple ذي البريد المخفي، وتجديد الجلسة. الأزرار جاهزة في الكود؛ المزودان كانا غير مفعّلين في المشروع عند الفحص بتاريخ 2026-10-04. لا تعتبر دخولًا اجتماعيًا حقيقيًا قد اختُبر حتى إعداد حسابات المزودين.
- تنبيهات انتهاء الوثائق داخل التطبيق تأتي من cron الموجود. تنبيهات الهاتف خارج التطبيق تحتاج إكمال Firebase ونشر نسخة `send-notifications` المحدّثة، ولا تعتمد عليها قبل اختبار جهاز فعلي.

## 6. Google Maps

- أنشئ مفاتيح منفصلة لأندرويد وآيفون، وقيّدها باسم الحزمة وتوقيع التطبيق/معرّف bundle. فعّل Maps SDK المناسب.
- Android: زوّد Gradle بخاصية `GOOGLE_MAPS_API_KEY`؛ لا تضع المفتاح في الكود.
- iOS: عيّن Build Setting باسم `GOOGLE_MAPS_API_KEY`؛ AppDelegate يمرره إلى SDK.
- عيّن `MAPS_ENABLED=true` في config.json بعد الإعداد. اختبر السموع–الخليل ودورا والقرى فعليًا قبل الاعتماد على أي خدمة توجيه.
- لوقت الوصول: فعّل Google Routes، واحفظ مفتاح خادم باسم `GOOGLE_ROUTES_API_KEY` في أسرار Supabase، وانشر وظيفة `estimate-arrival`. عيّن `ESTIMATES_ENABLED=true` بعد اختبار دقة التوجيه على الخطوط الفعلية. المفتاح لا يصل إلى التطبيق.
- التقدير يحتاج موقعًا حديثًا وحجزًا مصرحًا به. عند تعذر التوجيه لا يعرض التطبيق وقتًا مفترضًا.
- أدخل مسار الطريق المعتمد من لوحة الخطوط بصيغة GeoJSON LineString بترتيب المحطات، مثل `{"type":"LineString","coordinates":[[35.07,31.4],[35.08,31.45],[35.09,31.53]]}`. المثال توضيحي فقط وليس طريقًا رسميًا. بدون مسار معتمد يقترح التطبيق مواقف فقط.

## 7. Firebase والإشعارات

1. سجل تطبيقَي أندرويد وآيفون في Firebase بالمعرفات الصحيحة.
2. ضع `google-services.json` في `apps/mobile/android/app` و`GoogleService-Info.plist` في مشروع Runner على Mac، مع إضافته لعضوية target. الملفات مهملة من Git.
3. اضبط APNs وPush Notifications في Xcode، ثم عيّن `FIREBASE_ENABLED=true`.
4. أضف أسرار Supabase Edge Function: `FCM_SERVICE_ACCOUNT` (JSON للحساب الخدمي)، و`NOTIFICATION_WORKER_SECRET` (قيمة عشوائية طويلة). مفاتيح الحساب الخدمي لا تُرسل للتطبيقات.
5. انشر الوظيفة `send-notifications`؛ لديها فحص سر خاص بها بدل JWT المستخدم. خزّن عنوانها والسر في Supabase Vault.
6. أنشئ مهمة cron كل دقيقة باستخدام pg_net. مثال بعد إنشاء أسرار Vault بالأسماء المذكورة:

```sql
create extension if not exists pg_net with schema extensions;
select cron.schedule('rukkab-notifications','* * * * *', $job$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name='rukkab_notification_url'),
    headers := jsonb_build_object('Content-Type','application/json',
      'x-rukkab-worker-secret',(select decrypted_secret from vault.decrypted_secrets where name='rukkab_notification_secret')),
    body := '{}'::jsonb
  );
$job$);
```

عدم إعداد Firebase لا يمنع صندوق الإشعارات داخل التطبيق؛ تنبيهات الهاتف الخارجية لن تُرسل حتى اكتمال الإعداد. الوظيفة تعيد المحاولة حتى ٥ مرات مع تأخير متزايد، وتحذف الرموز المنتهية من FCM. راقب عدد المحاولات الفاشلة وسجلات Edge Function دون تسجيل الأسرار أو الوثائق.

## 8. التحقق قبل الإطلاق

- شغّل `npm run check` و`npm run test:browser` و`npm run test:mfa` مع تشغيل لوحة الإدارة محليًا. اختبار المصادقة الثنائية يستخدم بيانات وهمية ويغطي تحديث الصفحة، عزل التبويبات، انتهاء الجلسة، الرمز الخاطئ والأرقام العربية؛ يجب أيضًا إتمام التحقق بحساب حقيقي على staging.

- شغّل اختبارات المشروع، ثم اختبارات على Supabase staging براكبين وسائق وإدارة ومصادقة ثنائية.
- اختبر آخر مقعد باتصالَي قاعدة بيانات مستقلين، والحظر وتجاوز البيرميت باستخدام طلبات API مباشرة.
- اختبر رفع/تنزيل الوثائق والحظر وعرض الموقع من حساب غير مخول.
- اختبر GPS في الخلفية وموافقة المستخدم وقطع الشبكة وإعادة فتح التطبيق على أندرويد وآيفون فعليين. يجب ألا تُؤكد أي عملية غير متصلة.
- فعّل نسخًا احتياطية تناسب الخطة، ثم جرّب استرجاع نسخة على مشروع منفصل. لا تعتبر النسخ الاحتياطي فعالًا دون اختبار استرجاع.
- راقب زمن البحث والحجز، عمر تحديثات الموقع، الطلبات المنتهية والإشعارات الفاشلة. استخدم بيانات اصطناعية لاختبار الحمل المتوقع قبل إعلان الخدمة لجميع المحافظات.
- تحقق على staging من رفض نقطة ركوب خارج مسار GeoJSON، واقتراح نقطة مشتركة للركاب المتقاربين، وعدم تكرار تنبيه اقتراب السيارة، وإلغاء الوصول لتقديرات الرحلة بعد النزول أو الإلغاء.

