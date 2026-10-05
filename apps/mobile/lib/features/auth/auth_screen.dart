import '../../core/error_messages.dart';
import '../../shared/brand_mark.dart';
import '../../shared/motion_entrance.dart';
import 'package:flutter/foundation.dart';
import 'account_type_screen.dart';
import 'password_reset_screen.dart';
import 'email_confirmation_screen.dart';
import '../../core/repository.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/translations.dart';
import '../../core/driver_identity.dart';
import '../../shared/driver_identity_fields.dart';
import '../../core/rider_social_auth.dart';

class AuthScreen extends StatelessWidget {
  final bool recovery;
  const AuthScreen({super.key, this.recovery = false});
  @override
  Widget build(BuildContext context) => Navigator(
    key: ValueKey(recovery),
    onGenerateRoute: (_) => MaterialPageRoute<void>(
      builder: (_) => AuthFormScreen(recovery: recovery),
    ),
  );
}

class AuthFormScreen extends StatefulWidget {
  final bool recovery;
  final bool registration, driver;
  final Map<String, String>? driverDetails;
  const AuthFormScreen({
    super.key,
    this.recovery = false,
    this.registration = false,
    this.driver = false,
    this.driverDetails,
  });
  @override
  State<AuthFormScreen> createState() => _AuthFormScreenState();
}

class _AuthFormScreenState extends State<AuthFormScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(),
      _password = TextEditingController(),
      _name = TextEditingController(),
      _phone = TextEditingController();
  bool get _driverPortal => _signup ? widget.driver : _driverLogin;
  bool _driverLogin = false;
  bool _remember = true;
  DateTime? _birthDate;
  bool get _signup => widget.registration;
  bool _busy = false, _showPassword = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    _driverLogin = widget.driver;
    final details = widget.driverDetails;
    if (details != null) {
      _name.text = details['full_name'] ?? '';
      _phone.text = details['phone'] ?? '';
      _birthDate = DateTime.tryParse(details['date_of_birth'] ?? '');
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (widget.recovery) {
        await auth.updateUser(UserAttributes(password: _password.text));
        await auth.signOut();
      } else if (_signup) {
        await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {
            'full_name': _name.text.trim(),
            'account_type': _driverPortal ? 'driver' : 'rider',
            if (_driverPortal) ...{
              'phone': normalizePhone(_phone.text),
              'date_of_birth': dateOnly(_birthDate!),
            },
          },
          emailRedirectTo: 'io.rukkab.app://login-callback',
        );
        if (mounted) {
          final email = _email.text.trim();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => EmailConfirmationScreen(email: email),
            ),
          );
        }
      } else {
        sessionStorage.startAsPassenger = !_driverLogin;
        await sessionStorage.setRemember(_remember);
        await auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _message = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _socialSignIn(OAuthProvider provider) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await sessionStorage.setRemember(_remember);
      await signInRiderWithSocial(provider);
    } catch (e) {
      if (mounted) setState(() => _message = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: [
        IconButton(
          onPressed: language.toggle,
          icon: const Icon(Icons.language),
        ),
      ],
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(26),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: MotionEntrance(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandMark(size: 80)),
                  const SizedBox(height: 12),
                  Text(
                    'ركاب',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    language.text('الطريق بيجمعنا', 'Every road connects us'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  if (!widget.recovery) ...[
                    Text(
                      language.text(
                        _signup
                            ? (_driverPortal
                                  ? 'تسجيل سائق جديد'
                                  : 'تسجيل راكب جديد')
                            : 'تسجيل الدخول',
                        _signup
                            ? (_driverPortal
                                  ? 'Driver registration'
                                  : 'Rider registration')
                            : 'Sign in',
                      ),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (!_signup && !widget.recovery) ...[
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: false,
                          icon: const Icon(Icons.person_outline),
                          label: Text(language.text('راكب', 'Passenger')),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: const Icon(Icons.directions_bus_outlined),
                          label: Text(language.text('سائق', 'Driver')),
                        ),
                      ],
                      selected: {_driverLogin},
                      onSelectionChanged: _busy
                          ? null
                          : (selection) =>
                                setState(() => _driverLogin = selection.first),
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (_signup &&
                      _driverPortal &&
                      widget.driverDetails != null) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_outline),
                      title: Text(_name.text),
                      subtitle: Text(
                        language.text(
                          'الخطوة ٢: أنشئ بيانات الدخول',
                          'Step 2: create sign-in details',
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (_signup &&
                      _driverPortal &&
                      widget.driverDetails == null &&
                      !widget.recovery) ...[
                    DriverIdentityFields(
                      name: _name,
                      phone: _phone,
                      birthDate: _birthDate,
                      onBirthDate: (date) => setState(() => _birthDate = date),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      language.text(
                        'بعد تأكيد البريد: أضف السيارة ورخصة القيادة والتأمين والترخيص وصور السيارة، والبيرميت وخطه عند الحاجة. لا يبدأ العمل قبل اعتماد الإدارة.',
                        'After email confirmation, add the vehicle, license, insurance, registration, vehicle photos, and permit route where required. Admin approval is required before work.',
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_signup && !_driverPortal && !widget.recovery) ...[
                    TextFormField(
                      controller: _name,
                      decoration: InputDecoration(
                        labelText: language.text('الاسم الكامل', 'Full name'),
                      ),
                      validator: (v) => (v?.trim().length ?? 0) < 2
                          ? language.text(
                              'أدخل اسمك الكامل',
                              'Enter your full name',
                            )
                          : null,
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (!widget.recovery) ...[
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: language.text('البريد الإلكتروني', 'Email'),
                      ),
                      validator: (v) =>
                          v != null &&
                              RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v)
                          ? null
                          : language.text(
                              'أدخل بريدًا صحيحًا',
                              'Enter a valid email',
                            ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextFormField(
                    controller: _password,
                    obscureText: !_showPassword,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: language.text('كلمة المرور', 'Password'),
                      suffixIcon: IconButton(
                        tooltip: language.text(
                          'إظهار أو إخفاء كلمة المرور',
                          'Show or hide password',
                        ),
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    validator: (v) => (v?.length ?? 0) < 12
                        ? language.text(
                            '١٢ حرفًا على الأقل',
                            'At least 12 characters',
                          )
                        : null,
                  ),
                  if (!_signup && !widget.recovery)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _remember,
                      onChanged: _busy
                          ? null
                          : (value) =>
                                setState(() => _remember = value ?? true),
                      title: Text(
                        language.text('حفظ تسجيل الدخول', 'Remember me'),
                      ),
                    ),
                  const SizedBox(height: 20),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 15),
                      child: Text(
                        _message!,
                        style: const TextStyle(color: Colors.deepOrange),
                      ),
                    ),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(
                      widget.recovery
                          ? language.text('حفظ كلمة المرور', 'Save password')
                          : _signup
                          ? language.text('إنشاء حساب', 'Create account')
                          : language.text('تسجيل الدخول', 'Sign in'),
                    ),
                  ),
                  if (!widget.recovery) ...[
                    if (!_signup)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const AccountTypeScreen(),
                                ),
                              ),
                        child: Text(
                          language.text(
                            'إنشاء حساب جديد',
                            'Create a new account',
                          ),
                        ),
                      ),
                    if (!_signup && !_driverPortal && !widget.recovery) ...[
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _socialSignIn(OAuthProvider.google),
                        icon: const Text(
                          'G',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                        ),
                        label: Text(
                          language.text(
                            'المتابعة باستخدام Google',
                            'Continue with Google',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (defaultTargetPlatform == TargetPlatform.iOS)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _busy
                              ? null
                              : () => _socialSignIn(OAuthProvider.apple),
                          icon: const Icon(Icons.apple),
                          label: Text(
                            language.text(
                              'المتابعة باستخدام Apple',
                              'Continue with Apple',
                            ),
                          ),
                        ),
                      const SizedBox(height: 14),
                      Text(
                        language.text(
                          'للركاب فقط',
                          'For passenger accounts only',
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (!_signup)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const PasswordResetScreen(),
                                ),
                              ),
                        child: Text(
                          language.text(
                            'نسيت كلمة المرور؟',
                            'Forgot password?',
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
