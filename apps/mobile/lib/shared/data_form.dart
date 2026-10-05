import 'package:intl/intl.dart';
import '../core/palestine_time.dart';
import 'package:flutter/material.dart';
import '../core/repository.dart';
import '../core/translations.dart';
import '../core/input_normalization.dart';

class FormFieldSpec {
  final String key, arabic, english;
  final String type;
  final String initial;
  final Map<String, String>? options;
  final bool required;
  const FormFieldSpec(
    this.key,
    this.arabic,
    this.english, {
    this.type = 'text',
    this.initial = '',
    this.options,
    this.required = true,
  });
}

Future<Record?> showDataForm(
  BuildContext context,
  String title,
  List<FormFieldSpec> fields,
) => showDialog<Record>(
  context: context,
  builder: (_) => _DataForm(title: title, fields: fields),
);

class _DataForm extends StatefulWidget {
  final String title;
  final List<FormFieldSpec> fields;
  const _DataForm({required this.title, required this.fields});
  @override
  State<_DataForm> createState() => _DataFormState();
}

class _DataFormState extends State<_DataForm> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;
  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final field in widget.fields)
        field.key: TextEditingController(
          text: field.type == 'date' && DateTime.tryParse(field.initial) != null
              ? DateFormat(
                  'yyyy-MM-dd HH:mm',
                ).format(palestineTime(DateTime.parse(field.initial)))
              : field.initial,
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime _parseDate(String value) {
    final wall = DateFormat('yyyy-MM-dd HH:mm').parseStrict(value);
    return palestineWallTime(
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: widget.fields
              .map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: f.options != null
                      ? DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: f.initial.isEmpty ? null : f.initial,
                          decoration: InputDecoration(
                            labelText: language.text(f.arabic, f.english),
                          ),
                          items: f.options!.entries
                              .map(
                                (o) => DropdownMenuItem(
                                  value: o.key,
                                  child: Text(
                                    o.value,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => _controllers[f.key]!.text = v ?? '',
                          validator: (v) => v == null
                              ? language.text('اختر قيمة', 'Choose a value')
                              : null,
                        )
                      : TextFormField(
                          controller: _controllers[f.key],
                          keyboardType: f.type == 'number'
                              ? const TextInputType.numberWithOptions(
                                  decimal: true,
                                )
                              : TextInputType.text,
                          readOnly: f.type == 'date',
                          decoration: InputDecoration(
                            labelText: language.text(f.arabic, f.english),
                            helperText: f.type == 'date'
                                ? language.text(
                                    'توقيت فلسطين',
                                    'Palestine time',
                                  )
                                : null,
                          ),
                          onTap: f.type == 'date'
                              ? () async {
                                  var selected = palestineNow();
                                  try {
                                    selected = _parseDate(
                                      _controllers[f.key]!.text,
                                    );
                                  } on FormatException {
                                    // Empty new fields start at the current Palestine time.
                                  }
                                  final first = palestineNow();
                                  final last = first.add(
                                    const Duration(days: 3650),
                                  );
                                  final initial = selected.isBefore(first)
                                      ? first
                                      : selected.isAfter(last)
                                      ? last
                                      : selected;
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: initial,
                                    firstDate: first,
                                    lastDate: last,
                                  );
                                  if (date == null || !context.mounted) return;
                                  final time = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay.fromDateTime(
                                      selected,
                                    ),
                                  );
                                  if (time != null) {
                                    _controllers[f.key]!.text =
                                        DateFormat('yyyy-MM-dd HH:mm').format(
                                          palestineWallTime(
                                            date.year,
                                            date.month,
                                            date.day,
                                            time.hour,
                                            time.minute,
                                          ),
                                        );
                                  }
                                }
                              : null,
                          validator: (v) {
                            if (!f.required &&
                                (v == null || v.trim().isEmpty)) {
                              return null;
                            }
                            if (v == null || v.trim().isEmpty) {
                              return language.text(
                                'هذا الحقل مطلوب',
                                'Required',
                              );
                            }
                            if (f.type == 'number' &&
                                (num.tryParse(normalizeNumber(v)) == null ||
                                    num.parse(normalizeNumber(v)) < 0)) {
                              return language.text(
                                'أدخل رقمًا صحيحًا',
                                'Enter a valid number',
                              );
                            }
                            return null;
                          },
                        ),
                ),
              )
              .toList(),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(language.text('رجوع', 'Back')),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(context, {
            for (final f in widget.fields)
              f.key: f.type == 'number'
                  ? num.parse(normalizeNumber(_controllers[f.key]!.text))
                  : f.type == 'date'
                  ? _parseDate(
                      _controllers[f.key]!.text,
                    ).toUtc().toIso8601String()
                  : _controllers[f.key]!.text.trim(),
          });
        },
        child: Text(language.text('متابعة', 'Continue')),
      ),
    ],
  );
}
