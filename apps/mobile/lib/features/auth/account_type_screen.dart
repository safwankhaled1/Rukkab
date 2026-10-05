import 'package:flutter/material.dart';
import '../../core/translations.dart';
import 'auth_screen.dart';
import 'driver_signup_details_screen.dart';

/// Account type is chosen only during registration, never from a rider account.
class AccountTypeScreen extends StatelessWidget {
  const AccountTypeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(language.text('إنشاء حساب', 'Create account'))),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            language.text('كيف بدك تستخدم ركاب؟', 'How will you use Rukkab?'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Text(
            language.text(
              'اختار حسابك لنبدأ بخطوات واضحة.',
              'Choose an account to get started.',
            ),
          ),
          const SizedBox(height: 28),
          _choice(
            context,
            false,
            Icons.directions_bus_outlined,
            language.text('التسجيل كراكب', 'Register as a rider'),
            language.text(
              'ابحث عن رحلة واحجز مقعدك.',
              'Find a ride and reserve your seat.',
            ),
          ),
          const SizedBox(height: 16),
          _choice(
            context,
            true,
            Icons.airline_seat_recline_normal,
            language.text('التسجيل كسائق', 'Register as a driver'),
            language.text(
              'أضف بياناتك ووثائقك، ثم انتظر اعتماد الإدارة. يمكنك أيضًا حجز الرحلات كراكب.',
              'Submit your details and documents for admin approval. You can also book rides as a passenger.',
            ),
          ),
        ],
      ),
    ),
  );

  Widget _choice(
    BuildContext context,
    bool driver,
    IconData icon,
    String title,
    String subtitle,
  ) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => driver
              ? const DriverSignupDetailsScreen()
              : const AuthFormScreen(registration: true),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(subtitle),
            const SizedBox(height: 16),
            const Icon(Icons.arrow_forward_rounded),
          ],
        ),
      ),
    ),
  );
}
