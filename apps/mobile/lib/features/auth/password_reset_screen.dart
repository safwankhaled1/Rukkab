import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/translations.dart';
import '../../core/error_messages.dart';

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key});
  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _email = TextEditingController();
  final _form = GlobalKey<FormState>();
  String? _message;
  bool _busy = false;
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _email.text.trim(),
        redirectTo: 'io.rukkab.app://login-callback',
      );
      if (mounted) {
        setState(
          () => _message = language.text(
            'راجع بريدك لرابط الاستعادة',
            'Check your email for a reset link',
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _message = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(language.text('استعادة كلمة المرور', 'Reset password')),
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.mail_outline_rounded, size: 48),
                const SizedBox(height: 24),
                Text(
                  language.text(
                    'أدخل بريد حسابك لنرسل رابط الاستعادة.',
                    'Enter your account email to receive a reset link.',
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(
                    labelText: language.text('البريد الإلكتروني', 'Email'),
                  ),
                  validator: (value) =>
                      RegExp(
                        r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                      ).hasMatch(value?.trim() ?? '')
                      ? null
                      : language.text(
                          'أدخل بريدًا صحيحًا',
                          'Enter a valid email',
                        ),
                ),
                const SizedBox(height: 24),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(_message!),
                  ),
                FilledButton(
                  onPressed: _busy ? null : _reset,
                  child: Text(
                    language.text('إرسال رابط الاستعادة', 'Send reset link'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
