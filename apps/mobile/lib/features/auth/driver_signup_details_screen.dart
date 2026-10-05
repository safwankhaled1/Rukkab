import 'package:flutter/material.dart';
import '../../core/driver_identity.dart';
import '../../core/translations.dart';
import '../../shared/driver_identity_fields.dart';
import 'auth_screen.dart';

/// Collect personal details before email/password. No account is created here.
class DriverSignupDetailsScreen extends StatefulWidget {
  const DriverSignupDetailsScreen({super.key});
  @override
  State<DriverSignupDetailsScreen> createState() =>
      _DriverSignupDetailsScreenState();
}

class _DriverSignupDetailsScreenState extends State<DriverSignupDetailsScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _phone = TextEditingController();
  DateTime? _birthDate;
  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(language.text('التسجيل كسائق', 'Driver registration')),
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
                Text(
                  language.text('نتعرّف عليك أولًا', 'Let’s start with you'),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  language.text(
                    'اكتب بياناتك بالعربية أو الإنجليزية كما تظهر في رخصتك.',
                    'Enter your details in Arabic or English as shown on your license.',
                  ),
                ),
                const SizedBox(height: 28),
                DriverIdentityFields(
                  name: _name,
                  phone: _phone,
                  birthDate: _birthDate,
                  onBirthDate: (date) => setState(() => _birthDate = date),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () {
                    if (!_form.currentState!.validate()) return;
                    final details = {
                      'full_name': _name.text.trim(),
                      'phone': normalizePhone(_phone.text),
                      'date_of_birth': dateOnly(_birthDate!),
                    };
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AuthFormScreen(
                          registration: true,
                          driver: true,
                          driverDetails: details,
                        ),
                      ),
                    );
                  },
                  child: Text(
                    language.text(
                      'التالي: بيانات الدخول',
                      'Next: sign-in details',
                    ),
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
