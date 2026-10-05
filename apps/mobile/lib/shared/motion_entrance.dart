import 'package:flutter/material.dart';

/// Run once on entry; leave content and actions mounted throughout the motion.
class MotionEntrance extends StatelessWidget {
  final Widget child;
  const MotionEntrance({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (_, value, content) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - value)),
          child: content,
        ),
      ),
    );
  }
}
