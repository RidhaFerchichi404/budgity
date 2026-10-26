import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// The Budgity logo tile. Same geometry as assets/brand/budgity-icon.svg (1024 grid),
/// drawn directly so the app needs no SVG dependency.
class BudgityMark extends StatelessWidget {
  const BudgityMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Budgity logo',
    image: true,
    child: CustomPaint(size: Size.square(size), painter: const _MarkPainter()),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 1024);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 1024, 1024), const Radius.circular(232)),
      Paint()..color = AppPalette.primaryContainer,
    );
    canvas.translate(-40, 0);

    final stroke = Paint()
      ..color = AppPalette.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 96
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawLine(const Offset(348, 280), const Offset(348, 736), stroke);
    canvas.drawPath(_bowl(280, 488, 556, 104), stroke); // upper, shorter
    canvas.drawPath(_bowl(488, 736, 612, 124), stroke); // lower, longer

    canvas.drawCircle(const Offset(752, 296), 52, Paint()..color = AppPalette.onPrimaryContainer);
  }

  /// Stem → right edge → half-circle down → back to stem.
  static Path _bowl(double top, double bottom, double right, double r) => Path()
    ..moveTo(348, top)
    ..lineTo(right, top)
    ..arcToPoint(Offset(right, bottom), radius: Radius.circular(r))
    ..lineTo(348, bottom);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
