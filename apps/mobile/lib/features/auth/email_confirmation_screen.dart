import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/error_messages.dart';
import '../../core/translations.dart';

/// Registration data and password stay on the previous, disposed form.
class EmailConfirmationScreen extends StatefulWidget {
  final String email;
  const EmailConfirmationScreen({super.key, required this.email});
  @override
  State<EmailConfirmationScreen> createState() =>
      _EmailConfirmationScreenState();
}

class _EmailConfirmationScreenState extends State<EmailConfirmationScreen> {
  bool _busy = false;
  String? _message;
  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: widget.email,
        emailRedirectTo: 'io.rukkab.app://login-callback',
      );
      if (mounted) {
        setState(
          () => _message = language.text(
            'تم طلب إعادة إرسال رسالة التأكيد. راجع البريد والرسائل غير المرغوب فيها.',
            'Confirmation requested. Check your inbox and spam folder.',
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
    appBar: AppBar(title: Text(language.text('تأكيد البريد', 'Confirm email'))),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.mark_email_unread_outlined, size: 64),
              const SizedBox(height: 24),
              Text(
                language.text('باقي خطوة واحدة', 'One more step'),
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                language.text(
                  'افتح رسالة التأكيد واضغط الرابط، ثم ارجع للتطبيق وسجّل الدخول.',
                  'Open the confirmation email and follow its link, then return here and sign in.',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              SelectableText(
                widget.email,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(
                        context,
                      ).popUntil((route) => route.isFirst),
                child: Text(
                  language.text('العودة إلى تسجيل الدخول', 'Back to sign in'),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy ? null : _resend,
                child: Text(
                  language.text(
                    'إعادة إرسال رسالة التأكيد',
                    'Resend confirmation email',
                  ),
                ),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Text(_message!),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
