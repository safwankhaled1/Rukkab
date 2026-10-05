import { useEffect, useState, type FormEvent } from "react";
import {
  ArrowUpRight,
  Eye,
  EyeOff,
  Globe2,
  Route,
  ShieldCheck,
} from "lucide-react";
import { supabase } from "../data";
import { BrandMark } from "./BrandMark";
import { errorMessage } from "../core/errors";
export function Login({
  en,
  onLanguage,
  onDemo,
}: {
  en: boolean;
  onLanguage: () => void;
  onDemo: () => void;
}) {
  const [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [showPassword, setShowPassword] = useState(false);
  const submit = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (!supabase) return;
    setBusy(true);
    setError("");
    const f = new FormData(e.currentTarget);
    try {
      const { error } = await supabase.auth.signInWithPassword({
        email: String(f.get("email")).trim(),
        password: String(f.get("password")),
      });
      if (error) setError(errorMessage(error, en));
    } catch (error) {
      setError(errorMessage(error, en));
    } finally {
      setBusy(false);
    }
  };
  return (
    <div className="login-page">
      <section className="login-story">
        <div className="brand">
          <BrandMark size={52} />
          <span>
            ركاب<small>RUKKAB</small>
          </span>
        </div>
        <div>
          <div className="eyebrow">
            {en ? "PALESTINE, CONNECTED" : "فلسطين، أقرب"}
          </div>
          <h1>{en ? "Every road\nconnects us." : "الطريق\nبيجمعنا."}</h1>
          <p>
            {en
              ? "One place to manage drivers, riders, and journeys."
              : "مكان واحد لإدارة السائقين والركاب، وتسهيل كل رحلة."}
          </p>
          <div className="route-art">
            <i />
            <span>{en ? "As Samu" : "السموع"}</span>
            <b />
            <span>{en ? "Hebron" : "الخليل"}</span>
            <i />
          </div>
        </div>
        <small>
          {en ? "Rukkab operations center" : "مركز إدارة عمليات ركاب"}
        </small>
      </section>
      <section className="login-form">
        <button className="language-toggle secondary" onClick={onLanguage}>
          <Globe2 size={16} />
          {en ? "العربية" : "English"}
        </button>
        <div>
          <ShieldCheck size={32} className="teal" />
          <h2>
            {en ? "Welcome to the admin center" : "أهلًا في مركز الإدارة"}
          </h2>
          <p>
            {en
              ? "Sign in with your authorized administrative account."
              : "سجّل دخولك بحساب الإدارة المعتمد."}
          </p>
          {supabase ? (
            <form onSubmit={submit}>
              <label className="form-field">
                <span>{en ? "Email address" : "البريد الإلكتروني"}</span>
                <input
                  type="email"
                  name="email"
                  autoComplete="username"
                  required
                  dir="ltr"
                />
              </label>
              <label className="form-field">
                <span>{en ? "Password" : "كلمة المرور"}</span>
                <div className="password-field">
                  <input
                    type={showPassword ? "text" : "password"}
                    name="password"
                    autoComplete="current-password"
                    required
                    dir="ltr"
                  />
                  <button
                    type="button"
                    className="password-toggle"
                    aria-label={
                      en
                        ? "Show or hide password"
                        : "إظهار أو إخفاء كلمة المرور"
                    }
                    aria-pressed={showPassword}
                    onClick={() => setShowPassword(!showPassword)}
                  >
                    {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                  </button>
                </div>
              </label>
              {error && <div className="error-banner">{error}</div>}
              <button className="primary full-width" disabled={busy}>
                {en ? "Sign in securely" : "تسجيل الدخول"}
              </button>
              <button
                type="button"
                className="text-button"
                disabled={busy}
                onClick={async () => {
                  const email = (
                    document.querySelector("[name=email]") as HTMLInputElement
                  )?.value;
                  if (!email) {
                    setError(
                      en ? "Enter your email first" : "أدخل بريدك أولًا",
                    );
                    return;
                  }
                  setBusy(true);
                  try {
                    const { error } =
                      await supabase!.auth.resetPasswordForEmail(email.trim(), {
                        redirectTo: window.location.origin,
                      });
                    setError(
                      error
                        ? errorMessage(error, en)
                        : en
                          ? "Check your email for a reset link"
                          : "راجع بريدك لرابط استعادة كلمة المرور",
                    );
                  } catch (error) {
                    setError(errorMessage(error, en));
                  } finally {
                    setBusy(false);
                  }
                }}
              >
                {en ? "Forgot your password?" : "نسيت كلمة المرور؟"}
              </button>
            </form>
          ) : (
            <div className="setup-notice">
              {en
                ? "Connect Supabase using apps/admin/.env to enable live sign-in. You can explore a local demo now."
                : "اربط Supabase من ملف apps/admin/.env لتفعيل الدخول الحقيقي. يمكنك استعراض النسخة التجريبية الآن."}
            </div>
          )}
          <button className="secondary full-width" onClick={onDemo}>
            {en ? "Explore the demo" : "استعرض النسخة التجريبية"}
            <ArrowUpRight size={16} />
          </button>
          <p className="secure-caption">
            <ShieldCheck size={14} />
            {en
              ? "Two-factor authentication required for live administration"
              : "المصادقة الثنائية مطلوبة لإدارة النظام الحقيقي"}
          </p>
        </div>
      </section>
    </div>
  );
}
export function Mfa({ en }: { en: boolean }) {
  const [factor, setFactor] = useState(""),
    [qr, setQr] = useState(""),
    [secret, setSecret] = useState(""),
    [error, setError] = useState(""),
    [code, setCode] = useState(""),
    [busy, setBusy] = useState(false),
    [loading, setLoading] = useState(true),
    [expired, setExpired] = useState(false);

  function reportFailure(failure: unknown) {
    const message =
      failure instanceof Error
        ? failure.message
        : String((failure as { message?: string })?.message ?? failure);
    const failureCode = String((failure as { code?: string })?.code ?? "");
    if (
      /Auth session missing|session_not_found|ADMIN_SESSION_EXPIRED|refresh_token_not_found/i.test(
        message + " " + failureCode,
      )
    ) {
      setExpired(true);
      setFactor("");
      setQr("");
      setSecret("");
      setCode("");
      setError(
        en
          ? "Your sign-in session expired. Sign in again to continue securely."
          : "انتهت جلسة الدخول. سجّل دخولك مجددًا لإكمال التحقق بأمان.",
      );
    } else setError(errorMessage(failure, en));
  }
  async function requireSession() {
    const { data, error } = await supabase!.auth.getSession();
    if (error) throw error;
    if (!data.session) throw new Error("ADMIN_SESSION_EXPIRED");
  }
  useEffect(() => {
    let active = true;
    async function loadFactors() {
      try {
        await requireSession();
        const { data, error } = await supabase!.auth.mfa.listFactors();
        if (error) throw error;
        if (active)
          setFactor(data.totp.find((x) => x.status === "verified")?.id ?? "");
      } catch (failure) {
        if (active) reportFailure(failure);
      } finally {
        if (active) setLoading(false);
      }
    }
    void loadFactors();
    return () => {
      active = false;
    };
  }, []);

  async function enroll() {
    setBusy(true);
    setError("");
    try {
      await requireSession();
      const { data, error: listError } = await supabase!.auth.mfa.listFactors();
      if (listError) throw listError;
      // Replace only unfinished setup for this app, never a verified factor.
      for (const stale of data.all.filter(
        (x) =>
          x.status === "unverified" &&
          x.factor_type === "totp" &&
          x.friendly_name === "Rukkab admin",
      )) {
        const { error } = await supabase!.auth.mfa.unenroll({
          factorId: stale.id,
        });
        if (error) throw error;
      }
      const { data: result, error } = await supabase!.auth.mfa.enroll({
        factorType: "totp",
        friendlyName: "Rukkab admin",
      });
      if (error) throw error;
      setFactor(result.id);
      setQr(result.totp.qr_code);
      setSecret(result.totp.secret);
      setCode("");
    } catch (failure) {
      reportFailure(failure);
    } finally {
      setBusy(false);
    }
  }
  async function verify(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      await requireSession();
      const { error } = await supabase!.auth.mfa.challengeAndVerify({
        factorId: factor,
        code,
      });
      if (error) throw error;
      setQr("");
      setSecret("");
      setCode("");
    } catch (failure) {
      reportFailure(failure);
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="gate mfa-gate">
      <ShieldCheck size={40} className="teal" />
      <h1>{en ? "Protect your admin account" : "احمِ حساب الإدارة"}</h1>
      <p>
        {en
          ? "Open your authenticator app, choose Add account, then scan this QR. Your phone camera may open the browser instead."
          : "افتح تطبيق المصادقة، واختر إضافة حساب ثم مسح QR. كاميرا الهاتف العادية قد تفتح المتصفح بدل تطبيق المصادقة."}
      </p>
      {loading && (
        <p role="status">
          {en
            ? "Checking your sign-in session…"
            : "جارٍ التحقق من جلسة الدخول…"}
        </p>
      )}
      {!loading && !factor && !expired && (
        <button className="primary" disabled={busy} onClick={enroll}>
          {en ? "Set up two-factor authentication" : "إعداد المصادقة الثنائية"}
        </button>
      )}
      {qr && (
        <img
          className="qr"
          alt={en ? "Authenticator setup" : "رمز إعداد تطبيق المصادقة"}
          src={
            qr.startsWith("data:")
              ? qr
              : "data:image/svg+xml;charset=utf-8," + encodeURIComponent(qr)
          }
        />
      )}
      {secret && (
        <details className="manual-mfa">
          <summary>
            {en
              ? "Using the same phone? Enter a setup key"
              : "نفس الهاتف؟ استخدم مفتاح الإعداد اليدوي"}
          </summary>
          <p>
            {en
              ? "In your authenticator, add a time-based account named Rukkab using this key. Keep the key private."
              : "في تطبيق المصادقة أضف حسابًا باسم ركاب، واختر رمزًا يعتمد على الوقت، وأدخل هذا المفتاح. احتفظ به لنفسك."}
          </p>
          <code dir="ltr">{secret}</code>
        </details>
      )}
      {factor && !expired && (
        <form onSubmit={verify}>
          <label className="mfa-code">
            <span>
              {en ? "Six-digit verification code" : "رمز التحقق من ٦ أرقام"}
            </span>
            <input
              value={code}
              onChange={(e) =>
                setCode(
                  e.target.value
                    .replace(/[٠-٩]/g, (digit) =>
                      String(digit.charCodeAt(0) - 1632),
                    )
                    .replace(/[^0-9]/g, "")
                    .slice(0, 6),
                )
              }
              inputMode="numeric"
              autoComplete="one-time-code"
              pattern="[0-9]{6}"
              maxLength={6}
              required
              aria-label="Verification code"
              dir="ltr"
            />
          </label>
          <button className="primary" disabled={busy || code.length !== 6}>
            {busy
              ? en
                ? "Verifying…"
                : "جارٍ التحقق…"
              : en
                ? "Verify"
                : "تحقق"}
          </button>
        </form>
      )}
      {error && <p role="alert">{error}</p>}
      <button
        className="text-button"
        disabled={busy}
        onClick={() => supabase!.auth.signOut({ scope: "local" })}
      >
        {expired
          ? en
            ? "Return to sign in"
            : "العودة لتسجيل الدخول"
          : en
            ? "Sign out"
            : "تسجيل الخروج"}
      </button>
    </div>
  );
}
export function PasswordRecovery({
  en,
  onDone,
}: {
  en: boolean;
  onDone: () => void;
}) {
  const [error, setError] = useState("");
  return (
    <div className="gate">
      <h1>{en ? "Set a new password" : "عيّن كلمة مرور جديدة"}</h1>
      <form
        onSubmit={async (e) => {
          e.preventDefault();
          const f = new FormData(e.currentTarget);
          const { error } = await supabase!.auth.updateUser({
            password: String(f.get("password")),
          });
          if (error) setError(error.message);
          else onDone();
        }}
      >
        <input
          name="password"
          type="password"
          minLength={12}
          required
          autoComplete="new-password"
          aria-label="New password"
        />
        <button className="primary">
          {en ? "Save password" : "حفظ كلمة المرور"}
        </button>
      </form>
      {error && <p>{error}</p>}
    </div>
  );
}
