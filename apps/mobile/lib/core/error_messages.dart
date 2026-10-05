import 'package:supabase_flutter/supabase_flutter.dart';
import 'repository.dart';
import 'translations.dart';

// Translate known service failures without showing database internals to users.
String errorMessage(Object error) {
  final code = error is AppFailure
      ? error.code
      : error is PostgrestException
      ? error.message
      : error is AuthException
      ? error.code ?? error.message
      : '';
  final messages = <String, List<String>>{
    'APPLICATION_ALREADY_SUBMITTED': [
      'طلبك قيد المراجعة ولا يمكن تعديله الآن.',
      'Your application is under review and cannot be edited now.',
    ],
    'APPLICATION_NOT_SUBMITTED': [
      'أرسل الطلب المكتمل أولًا.',
      'Submit the completed application first.',
    ],
    'APPLICATION_DRAFT_REQUIRED': [
      'اختر مسودة سيارة قابلة للتعديل.',
      'Choose an editable vehicle draft.',
    ],
    'VALID_CAPACITY_REQUIRED': [
      'أدخل عدد مقاعد صحيحًا من ١ إلى ٨٠.',
      'Enter a capacity between 1 and 80.',
    ],
    'VEHICLE_PLATE_REQUIRED': [
      'أدخل نمرة السيارة.',
      'Enter the vehicle plate.',
    ],
    'PERMIT_DETAILS_REQUIRED': [
      'أكمل اسم صاحب البيرميت وخطه.',
      'Complete the permit holder and route.',
    ],
    'EMAIL_CONFIRMATION_REQUIRED': [
      'أكد بريدك الإلكتروني ثم تابع.',
      'Confirm your email, then continue.',
    ],
    'OFFLINE': [
      'الاتصال مقطوع. اتصل بالإنترنت وحاول مجددًا.',
      'You are offline. Reconnect and try again.',
    ],
    'NO_SEATS': [
      'المقاعد لم تعد متاحة. ابحث مجددًا.',
      'Those seats are no longer available. Search again.',
    ],
    'PERMIT_ROUTE_MISMATCH': [
      'هذه الرحلة خارج خط السيارة المعتمد.',
      'This journey is outside the approved vehicle route.',
    ],
    'DRIVER_NOT_APPROVED': [
      'يلزم اعتماد السيارة ووثائقها قبل استقبال الحجوزات.',
      'The vehicle and its documents must be approved first.',
    ],
    'DRIVER_ACCOUNT_REQUIRED': [
      'هذه الميزة لحساب سائق مستقل. لا يمكن تحويل حساب الراكب.',
      'A separate driver account is required. Rider accounts cannot be converted.',
    ],
    'DRIVER_IDENTITY_REQUIRED': [
      'أكمل الاسم الكامل وتاريخ الميلاد ورقم الهاتف الصحيح.',
      'Complete your full name, date of birth and valid phone number.',
    ],
    'provider_disabled': [
      'طريقة الدخول غير مفعلة بعد. استخدم البريد الإلكتروني حاليًا.',
      'This sign-in method is not enabled yet. Use email for now.',
    ],
    'SOCIAL_SIGNIN_RIDERS_ONLY': [
      'الدخول بحساب Google أو Apple متاح للركاب فقط. استخدم البريد الإلكتروني لحساب السائق.',
      'Google and Apple sign-in are for riders. Use email for driver accounts.',
    ],
    'VEHICLE_TIME_CONFLICT': [
      'موعد الرحلة يتعارض مع رحلة أخرى للسيارة.',
      'This time overlaps another journey for the vehicle.',
    ],
    'VEHICLE_ALREADY_ON_TRIP': [
      'أنهِ الرحلة الحالية قبل بدء رحلة أخرى.',
      'Finish the current journey before starting another.',
    ],
    'PASSENGERS_REMAIN': [
      'أكد نزول الركاب قبل إنهاء الرحلة أو إلغائها.',
      'Confirm passenger drop-off before finishing or cancelling.',
    ],
    'CANNOT_BOOK_OWN_VEHICLE': [
      'لا يمكنك الحجز في سيارتك.',
      'You cannot book your own vehicle.',
    ],
    'PICKUP_REQUIRED': [
      'حدد نقطة الركوب والانطلاق والوجهة.',
      'Choose your pickup point, origin and destination.',
    ],
    'LOCATION_PERMISSION_REQUIRED': [
      'فعّل خدمة الموقع وإذن الوصول إليه لتحديد نقطة الركوب.',
      'Enable location services and permission to choose your pickup.',
    ],
    'DOCUMENT_FORMAT': [
      'اختر صورة JPG أو PNG للسيارة، وصورة أو PDF للوثائق.',
      'Use JPG or PNG vehicle photos; documents may also be PDF.',
    ],
    'DOCUMENT_EXPIRY_REQUIRED': [
      'أدخل تاريخ انتهاء الوثيقة.',
      'Enter the document expiry date.',
    ],
    'DOCUMENT_UPLOAD_REQUIRED': [
      'ارفع ملف الوثيقة أولًا.',
      'Upload the document first.',
    ],
    'DOCUMENT_TOO_LARGE': [
      'حجم الملف يتجاوز ١٠ ميغابايت.',
      'The file exceeds 10 MB.',
    ],
    'WAIT_FIVE_MINUTES': [
      'انتظر خمس دقائق بعد الوصول لنقطة الراكب.',
      'Wait five minutes after arriving at the passenger pickup.',
    ],
    'invalid_credentials': [
      'البريد أو كلمة المرور غير صحيحة.',
      'The email or password is incorrect.',
    ],
    'email_not_confirmed': [
      'أكد بريدك الإلكتروني قبل تسجيل الدخول.',
      'Confirm your email before signing in.',
    ],
    'over_email_send_rate_limit': [
      'انتظر قليلًا قبل طلب رسالة جديدة.',
      'Wait a moment before requesting another email.',
    ],
    'user_already_exists': [
      'هذا البريد مسجل. جرّب الدخول أو استعادة كلمة المرور.',
      'This email is registered. Sign in or reset your password.',
    ],
  };
  final message = messages[code];
  return message == null
      ? language.text(
          'تعذّر تنفيذ العملية. تحقق من الاتصال وحدّث الصفحة ثم حاول مجددًا.',
          'The action could not be completed. Check your connection, refresh and try again.',
        )
      : language.text(message[0], message[1]);
}
