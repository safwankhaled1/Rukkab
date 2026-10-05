import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/repository.dart';
import '../../core/translations.dart';
import '../../core/driver_identity.dart';
import '../../core/input_normalization.dart';
import '../../core/error_messages.dart';
import '../../core/palestine_time.dart';
import '../../shared/driver_identity_fields.dart';

/// Each completed page saves a draft. Only the final action submits for review.
class DriverOnboardingScreen extends StatefulWidget {
  final RideRepository repository;
  final Record? vehicle;
  final Future<void> Function() onRefresh;
  const DriverOnboardingScreen({
    super.key,
    required this.repository,
    this.vehicle,
    required this.onRefresh,
  });
  @override
  State<DriverOnboardingScreen> createState() => _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState extends State<DriverOnboardingScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _phone = TextEditingController(),
      _plate = TextEditingController(),
      _owner = TextEditingController(),
      _capacity = TextEditingController(),
      _permitOwner = TextEditingController(),
      _permitLine = TextEditingController();
  DateTime? _birthDate;
  String _kind = 'minibus', _state = 'draft';
  String? _vehicleId, _error, _reviewNote;
  int _step = 0;
  bool _busy = true;
  List<Record> _documents = [];
  List<String> get _required => [
    'license',
    if (_kind != 'taxi') 'permit',
    'insurance',
    'registration',
    'vehicle_photo',
  ];
  String _documentName(String kind) => switch (kind) {
    'license' => language.text('رخصة القيادة', 'Driving license'),
    'permit' => language.text('البيرميت', 'Permit'),
    'insurance' => language.text('التأمين', 'Insurance'),
    'registration' => language.text('ترخيص السيارة', 'Vehicle registration'),
    _ => language.text('صورة السيارة', 'Vehicle photo'),
  };
  bool _hasDocument(String kind) => _documents.any(
    (d) =>
        d['kind'] == kind &&
        (kind == 'vehicle_photo' ||
            (DateTime.tryParse(
                  d['expires_on'] ?? '',
                )?.isBefore(DateTime.parse(dateOnly(palestineNow()))) ==
                false)),
  );
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DriverOnboardingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vehicle != widget.vehicle && _vehicleId != null) {
      _refreshApplicationState();
    }
  }

  Future<void> _refreshApplicationState() async {
    try {
      final application = await widget.repository.client
          .from('driver_applications')
          .select()
          .eq('vehicle_id', _vehicleId!)
          .maybeSingle();
      if (!mounted || application == null) {
        return;
      }
      setState(() {
        final next = application['state'] as String;
        if (next == 'rejected' && _state != 'rejected') {
          _step = 2;
        }
        _state = next;
        _reviewNote = application['review_note'];
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = errorMessage(error));
      }
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _phone,
      _plate,
      _owner,
      _capacity,
      _permitOwner,
      _permitLine,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profile = await widget.repository.profile();
      final identity = await widget.repository.driverIdentity();
      _name.text = profile['full_name'] ?? '';
      _phone.text = identity?['phone'] ?? '';
      _birthDate = DateTime.tryParse(identity?['date_of_birth'] ?? '');
      final vehicle = widget.vehicle;
      if (vehicle != null) {
        _vehicleId = vehicle['id'];
        _plate.text = vehicle['plate'];
        _kind = vehicle['kind'];
        _capacity.text = '${vehicle['capacity']}';
        _permitLine.text = vehicle['permit_line'] ?? '';
        final ownership = await widget.repository.client
            .from('vehicle_ownership')
            .select()
            .eq('vehicle_id', _vehicleId!)
            .maybeSingle();
        _owner.text = ownership?['vehicle_owner_name'] ?? '';
        _permitOwner.text = ownership?['permit_holder_name'] ?? '';
        await _reloadDocuments();
        final application = await widget.repository.client
            .from('driver_applications')
            .select()
            .eq('vehicle_id', _vehicleId!)
            .maybeSingle();
        _state = application?['state'] ?? 'draft';
        _reviewNote = application?['review_note'];
        _step = 2;
      } else if (_birthDate != null && validDriverPhone(_phone.text)) {
        _step = 1;
      }
    } catch (e) {
      _error = errorMessage(e);
    }
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  Future<void> _reloadDocuments() async {
    _documents = await widget.repository.list(
      'documents',
      key: 'vehicle_id',
      value: _vehicleId,
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _error = errorMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _next() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    await _run(() async {
      if (_step == 0) {
        await widget.repository.accountAction('driver_identity', {
          'full_name': _name.text.trim(),
          'phone': normalizePhone(_phone.text),
          'date_of_birth': dateOnly(_birthDate!),
        });
      } else if (_step == 1) {
        final payload = <String, dynamic>{
          'plate': _plate.text.trim(),
          'kind': _kind,
          'capacity': int.parse(normalizeNumber(_capacity.text)),
          'vehicle_owner_name': _owner.text.trim(),
          'permit_holder_name': _permitOwner.text.trim(),
          'permit_line': _permitLine.text.trim(),
        };
        if (_vehicleId == null) {
          final saved = await widget.repository.rpc('account_action', {
            'a': 'register_vehicle',
            'p': payload,
          });
          _vehicleId = saved['id'];
        } else {
          payload['vehicle_id'] = _vehicleId;
          await widget.repository.accountAction(
            'update_vehicle_draft',
            payload,
          );
        }
        await widget.onRefresh();
      } else if (_step == 2 && _required.any((k) => !_hasDocument(k))) {
        return;
      } else if (_step == 3) {
        await widget.repository.rpc('submit_driver_application', {
          'vehicle': _vehicleId,
        });
        _state = 'submitted';
        await widget.onRefresh();
        return;
      }
      if (mounted) {
        setState(() => _step++);
      }
    });
  }

  Future<void> _upload(String kind) async {
    DateTime? expiry;
    if (kind != 'vehicle_photo') {
      expiry = await showDatePicker(
        context: context,
        initialDate: palestineNow().add(const Duration(days: 365)),
        firstDate: DateTime.parse(dateOnly(palestineNow())),
        lastDate: palestineNow().add(const Duration(days: 3650)),
      );
      if (expiry == null) {
        return;
      }
    }
    final file = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: kind == 'vehicle_photo'
          ? ['jpg', 'jpeg', 'png']
          : ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    if (file == null || file.files.single.bytes == null || !mounted) {
      return;
    }
    await _run(() async {
      await widget.repository.uploadDocument(
        vehicleId: _vehicleId!,
        kind: kind,
        filename: file.files.single.name,
        bytes: file.files.single.bytes!,
        expiresOn: expiry == null ? null : dateOnly(expiry),
      );
      await _reloadDocuments();
      if (mounted && _required.every(_hasDocument)) {
        setState(() => _step = 3);
      }
    });
  }

  Widget _field(
    TextEditingController controller,
    String ar,
    String en, {
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: language.text(ar, en)),
      validator: (v) {
        if (v == null || v.trim().isEmpty) {
          return language.text('هذه الخانة مطلوبة', 'Required');
        }
        if (number) {
          final n = int.tryParse(normalizeNumber(v));
          if (n == null || n < 1 || n > 80) {
            return language.text(
              'من ١ إلى ٨٠ مقعدًا',
              'Between 1 and 80 seats',
            );
          }
        }
        return null;
      },
    ),
  );
  @override
  Widget build(BuildContext context) {
    final submitted = _state == 'submitted' || _state == 'approved';
    final titles = [
      language.text('بياناتك الشخصية', 'Your details'),
      language.text('السيارة والبيرميت', 'Vehicle and permit'),
      language.text('الوثائق المطلوبة', 'Required documents'),
      language.text('راجع وأرسل الطلب', 'Review and submit'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(language.text('تسجيل السائق', 'Driver application')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_state == 'rejected')
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      language.text(
                            'تحتاج بياناتك إلى تعديل قبل إعادة الإرسال.',
                            'Update your details before resubmitting.',
                          ) +
                          (_reviewNote == null || _reviewNote!.isEmpty
                              ? ''
                              : '\n${_reviewNote!}'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              if (submitted) ...[
                const Icon(Icons.task_alt, size: 72, color: Color(0xff438454)),
                const SizedBox(height: 24),
                Text(
                  language.text(
                    'وصل طلبك للإدارة',
                    'Your application was received',
                  ),
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  language.text(
                    'سنبلغك بنتيجة المراجعة. يمكنك استخدام حسابك كراكب أثناء الانتظار.',
                    'We will notify you after review. You can travel as a passenger while waiting.',
                  ),
                ),
              ] else ...[
                Text(
                  language.text(
                    'الخطوة ${_step + 1} من ٤',
                    'Step ${_step + 1} of 4',
                  ),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: (_step + 1) / 4),
                const SizedBox(height: 24),
                Text(
                  titles[_step],
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  language.text(
                    'نحفظ تقدمك. لن يُرسل طلب المراجعة حتى تضغط إرسال الطلب في النهاية.',
                    'Your progress is saved. Review starts only after you submit at the end.',
                  ),
                ),
                const SizedBox(height: 24),
                Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_step == 0)
                        DriverIdentityFields(
                          name: _name,
                          phone: _phone,
                          birthDate: _birthDate,
                          onBirthDate: (date) =>
                              setState(() => _birthDate = date),
                        ),
                      if (_step == 1) ...[
                        _field(_plate, 'نمرة السيارة', 'Vehicle plate'),
                        _field(
                          _owner,
                          'اسم مالك السيارة حسب الترخيص',
                          'Registered vehicle owner',
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: _kind,
                          decoration: InputDecoration(
                            labelText: language.text(
                              'نوع السيارة',
                              'Vehicle type',
                            ),
                          ),
                          items: ['taxi', 'minibus', 'medium_bus', 'large_bus']
                              .map(
                                (k) => DropdownMenuItem(
                                  value: k,
                                  child: Text(switch (k) {
                                    'taxi' => language.text('تكسي', 'Taxi'),
                                    'minibus' => language.text(
                                      'مونيت',
                                      'Minibus',
                                    ),
                                    'medium_bus' => language.text(
                                      'باص وسط',
                                      'Medium bus',
                                    ),
                                    _ => language.text('باص كبير', 'Large bus'),
                                  }),
                                ),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _kind = v!),
                        ),
                        const SizedBox(height: 16),
                        _field(
                          _capacity,
                          'عدد مقاعد الركاب',
                          'Passenger capacity',
                          number: true,
                        ),
                        if (_kind != 'taxi') ...[
                          _field(
                            _permitOwner,
                            'اسم صاحب البيرميت',
                            'Permit holder name',
                          ),
                          _field(
                            _permitLine,
                            'الخط كما يظهر في البيرميت',
                            'Line as shown on permit',
                          ),
                        ],
                      ],
                      if (_step == 2)
                        ..._required.map(
                          (kind) => Card(
                            child: ListTile(
                              leading: Icon(
                                _hasDocument(kind)
                                    ? Icons.check_circle
                                    : Icons.upload_file,
                                color: _hasDocument(kind)
                                    ? const Color(0xff438454)
                                    : null,
                              ),
                              title: Text(_documentName(kind)),
                              subtitle: Text(
                                language.text(
                                  kind == 'vehicle_photo'
                                      ? 'صورة واضحة للسيارة'
                                      : 'اختر تاريخ الانتهاء ثم ارفع الوثيقة',
                                  kind == 'vehicle_photo'
                                      ? 'Clear vehicle photo'
                                      : 'Choose expiry date, then upload',
                                ),
                              ),
                              trailing: TextButton(
                                onPressed: _busy ? null : () => _upload(kind),
                                child: Text(
                                  language.text(
                                    _hasDocument(kind) ? 'تعديل' : 'رفع',
                                    _hasDocument(kind) ? 'Replace' : 'Upload',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_step == 3) ...[
                        ListTile(
                          title: Text(_name.text),
                          subtitle: Text(_phone.text),
                        ),
                        ListTile(
                          title: Text(_plate.text),
                          subtitle: Text('${_owner.text}\n${_permitLine.text}'),
                        ),
                        ..._required.map(
                          (k) => ListTile(
                            leading: const Icon(Icons.check_circle_outline),
                            title: Text(_documentName(k)),
                          ),
                        ),
                        Text(
                          language.text(
                            'تأكد أن البيانات مطابقة للوثائق. لا يبدأ العمل قبل اعتماد الإدارة.',
                            'Ensure details match your documents. Work starts after admin approval.',
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed:
                            _busy ||
                                (_step == 2 &&
                                    _required.any((k) => !_hasDocument(k)))
                            ? null
                            : _next,
                        child: Text(
                          language.text(
                            _step == 3 ? 'إرسال الطلب للإدارة' : 'حفظ ومتابعة',
                            _step == 3
                                ? 'Submit application'
                                : 'Save and continue',
                          ),
                        ),
                      ),
                      if (_step > 0)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _step--),
                          child: Text(language.text('السابق', 'Back')),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
