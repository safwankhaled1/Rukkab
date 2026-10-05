import 'dart:async';
import 'package:flutter/material.dart';
import '../core/booking_rules.dart';
import '../core/translations.dart';

/// Only this small control ticks, rather than rebuilding the booking list.
class NoShowButton extends StatefulWidget {
  final DateTime? arrivedAt, startsAt;
  final bool busy;
  final VoidCallback onPressed;
  const NoShowButton({
    super.key,
    required this.arrivedAt,
    required this.startsAt,
    required this.busy,
    required this.onPressed,
  });
  @override
  State<NoShowButton> createState() => _NoShowButtonState();
}

class _NoShowButtonState extends State<NoShowButton> {
  Timer? _timer;
  Duration? get _wait =>
      noShowWait(widget.arrivedAt, widget.startsAt, DateTime.now());
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant NoShowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.arrivedAt != widget.arrivedAt ||
        oldWidget.startsAt != widget.startsAt) {
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (_wait != null && _wait! > Duration.zero) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (_wait == null || _wait == Duration.zero) _timer?.cancel();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wait = _wait;
    final seconds = ((wait?.inMilliseconds ?? 0) / 1000).ceil();
    final countdown =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Tooltip(
      message: language.text(
        'عدم الحضور يتطلب تسجيل الوصول وانتظار ٥ دقائق وبلوغ موعد الرحلة.',
        'Record arrival, wait five minutes and reach the departure time before a no-show.',
      ),
      child: OutlinedButton(
        onPressed: !widget.busy && wait == Duration.zero
            ? widget.onPressed
            : null,
        child: Text(
          wait == null
              ? language.text(
                  'عدم حضور · سجّل الوصول أولًا',
                  'No-show · record arrival first',
                )
              : wait > Duration.zero
              ? language.text(
                  'عدم حضور بعد $countdown',
                  'No-show in $countdown',
                )
              : language.text('عدم حضور', 'No-show'),
        ),
      ),
    );
  }
}
