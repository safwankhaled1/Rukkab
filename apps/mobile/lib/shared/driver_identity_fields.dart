import 'package:flutter/material.dart';
import '../core/driver_identity.dart';
import '../core/palestine_time.dart';
import '../core/translations.dart';

class DriverIdentityFields extends StatelessWidget {
  final TextEditingController name, phone;
  final DateTime? birthDate;
  final ValueChanged<DateTime> onBirthDate;
  const DriverIdentityFields({
    super.key,
    required this.name,
    required this.phone,
    required this.birthDate,
    required this.onBirthDate,
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextFormField(
        controller: name,
        autofillHints: const [AutofillHints.name],
        decoration: InputDecoration(
          labelText: language.text(
            'الاسم الكامل حسب الرخصة',
            'Full name as on license',
          ),
        ),
        validator: (v) => validDriverName(v ?? '')
            ? null
            : language.text(
                'أدخل الاسم الكامل، بما فيه اسم العائلة',
                'Enter your full name, including family name',
              ),
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: phone,
        keyboardType: TextInputType.phone,
        textDirection: TextDirection.ltr,
        autofillHints: const [AutofillHints.telephoneNumber],
        decoration: InputDecoration(
          labelText: language.text('رقم الهاتف', 'Phone number'),
          hintText: '059… / +970…',
        ),
        validator: (v) => validDriverPhone(v ?? '')
            ? null
            : language.text(
                'أدخل رقمًا صحيحًا مع رمز الدولة مثل ‎+970',
                'Enter a valid number with country code, e.g. +970',
              ),
      ),
      const SizedBox(height: 14),
      FormField<DateTime>(
        initialValue: birthDate,
        validator: (_) => birthDate == null
            ? language.text('اختر تاريخ الميلاد', 'Choose your date of birth')
            : null,
        builder: (field) => InkWell(
          onTap: () async {
            final now = palestineNow();
            final date = await showDatePicker(
              context: context,
              initialDate: birthDate ?? DateTime(now.year - 25, 1, 1),
              firstDate: DateTime(1900),
              lastDate: DateTime(
                now.year,
                now.month,
                now.day,
              ).subtract(const Duration(days: 1)),
            );
            if (date != null) {
              field.didChange(date);
              onBirthDate(date);
            }
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: language.text('تاريخ الميلاد', 'Date of birth'),
              errorText: field.errorText,
              suffixIcon: const Icon(Icons.calendar_month),
            ),
            child: Text(
              birthDate == null
                  ? language.text('اختر التاريخ', 'Choose a date')
                  : dateOnly(birthDate!),
            ),
          ),
        ),
      ),
    ],
  );
}

Future<Map<String, dynamic>?> showDriverIdentityForm(
  BuildContext context, {
  required String fullName,
  String? phone,
  String? dateOfBirth,
}) async {
  final nameController = TextEditingController(text: fullName);
  final phoneController = TextEditingController(text: phone ?? '');
  var birthDate = DateTime.tryParse(dateOfBirth ?? '');
  final form = GlobalKey<FormState>();
  try {
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(language.text('بيانات السائق', 'Driver identity')),
          content: SingleChildScrollView(
            child: Form(
              key: form,
              child: DriverIdentityFields(
                name: nameController,
                phone: phoneController,
                birthDate: birthDate,
                onBirthDate: (value) => setState(() => birthDate = value),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(language.text('إلغاء', 'Cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(context, {
                    'full_name': nameController.text.trim(),
                    'phone': normalizePhone(phoneController.text),
                    'date_of_birth': dateOnly(birthDate!),
                  });
                }
              },
              child: Text(
                language.text('حفظ وإرسال للمراجعة', 'Save for review'),
              ),
            ),
          ],
        ),
      ),
    );
  } finally {
    // Dialog exit animations may still reference controllers until next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      phoneController.dispose();
    });
  }
}
