import 'package:flutter/material.dart';

/// Native vector counterpart of assets/brand/rukkab-symbol.svg.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 44});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'ركاب | Rukkab',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _BrandPainter()),
    ),
  );
}

class _BrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 104, size.height / 104);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(4, 4, 96, 96),
        const Radius.circular(29),
      ),
      Paint()..color = const Color(0xff203b30),
    );
    final road = Path()
      ..moveTo(29, 78)
      ..lineTo(29, 38)
      ..quadraticBezierTo(29, 25, 43, 25)
      ..lineTo(57, 25)
      ..quadraticBezierTo(74, 25, 74, 40)
      ..quadraticBezierTo(74, 55, 57, 55)
      ..lineTo(44, 55)
      ..lineTo(76, 79);
    canvas.drawPath(
      road,
      Paint()
        ..color = const Color(0xffffad45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final guide = Path()
      ..moveTo(29, 69)
      ..lineTo(29, 40)
      ..quadraticBezierTo(29, 25, 43, 25)
      ..lineTo(57, 25);
    final linePaint = Paint()
      ..color = const Color(0xffffe18a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (final metric in guide.computeMetrics()) {
      for (double start = 0; start < metric.length; start += 10) {
        canvas.drawPath(
          metric.extractPath(start, (start + 3).clamp(0, metric.length)),
          linePaint,
        );
      }
    }
    canvas.drawCircle(
      const Offset(29, 79),
      7,
      Paint()..color = const Color(0xffd9eea9),
    );
    canvas.drawCircle(
      const Offset(76, 79),
      7,
      Paint()..color = const Color(0xffd9eea9),
    );
    canvas.drawCircle(
      const Offset(57, 25),
      4,
      Paint()..color = const Color(0xffffe18a),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
