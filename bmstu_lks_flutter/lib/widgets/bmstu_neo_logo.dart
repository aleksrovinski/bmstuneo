import 'dart:math' as math;
import 'package:flutter/material.dart';

class BmstuNeoLogo extends StatelessWidget {
  final double size;
  final bool showBadge;

  const BmstuNeoLogo({
    super.key,
    this.size = 76,
    this.showBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.26),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF070E1E),
            Color(0xFF002966),
            Color(0xFF0052CC),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00D2FF).withValues(alpha: 0.3),
            blurRadius: size * 0.28,
            offset: Offset(0, size * 0.08),
          ),
        ],
        border: Border.all(
          color: const Color(0xFF00D2FF).withValues(alpha: 0.6),
          width: math.max(1.5, size * 0.02),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.25),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Ambient Radial Glow
            Positioned(
              top: size * 0.1,
              child: Container(
                width: size * 0.7,
                height: size * 0.7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00D2FF).withValues(alpha: 0.14),
                ),
              ),
            ),
            // Custom Painted Vector Monogram
            CustomPaint(
              size: Size(size, size),
              painter: _BmstuNeoLogoPainter(showBadge: showBadge),
            ),
          ],
        ),
      ),
    );
  }
}

class _BmstuNeoLogoPainter extends CustomPainter {
  final bool showBadge;

  _BmstuNeoLogoPainter({required this.showBadge});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 512.0;

    // Tech circuit lines
    final techPaint = Paint()
      ..color = const Color(0xFF00D2FF).withValues(alpha: 0.4)
      ..strokeWidth = 3 * scale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(80 * scale, 160 * scale),
      Offset(140 * scale, 160 * scale),
      techPaint,
    );
    canvas.drawLine(
      Offset(432 * scale, 160 * scale),
      Offset(372 * scale, 160 * scale),
      techPaint,
    );

    final dotPaint = Paint()
      ..color = const Color(0xFF00FFF0)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(140 * scale, 160 * scale), 4 * scale, dotPaint);
    canvas.drawCircle(Offset(372 * scale, 160 * scale), 4 * scale, dotPaint);

    // Left Pillar of N
    final leftPillar = RRect.fromRectAndRadius(
      Rect.fromLTRB(148 * scale, 132 * scale, 214 * scale, 350 * scale),
      Radius.circular(16 * scale),
    );
    final pillarPaint = Paint()
      ..color = const Color(0xFF0070F3)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(leftPillar, pillarPaint);

    // Right Pillar of N
    final rightPillar = RRect.fromRectAndRadius(
      Rect.fromLTRB(298 * scale, 132 * scale, 364 * scale, 350 * scale),
      Radius.circular(16 * scale),
    );
    canvas.drawRRect(rightPillar, pillarPaint);

    // Diagonal Rocket Slash of N
    final diagPath = Path()
      ..moveTo(180 * scale, 142 * scale)
      ..lineTo(332 * scale, 350 * scale)
      ..arcToPoint(
        Offset(360 * scale, 351 * scale),
        radius: Radius.circular(12 * scale),
      )
      ..lineTo(362 * scale, 348 * scale)
      ..arcToPoint(
        Offset(359 * scale, 322 * scale),
        radius: Radius.circular(12 * scale),
      )
      ..lineTo(208 * scale, 114 * scale)
      ..arcToPoint(
        Offset(180 * scale, 113 * scale),
        radius: Radius.circular(12 * scale),
      )
      ..close();

    final diagPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF0070F3), Color(0xFF00D2FF), Color(0xFF00FFF0)],
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(diagPath, diagPaint);

    // Rocket Apex at Top Center
    final apexPath = Path()
      ..moveTo(256 * scale, 76 * scale)
      ..lineTo(294 * scale, 142 * scale)
      ..lineTo(218 * scale, 142 * scale)
      ..close();

    final apexPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Colors.white, Color(0xFF99E6FF)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(218 * scale, 76 * scale, 76 * scale, 66 * scale))
      ..style = PaintingStyle.fill;
    canvas.drawPath(apexPath, apexPaint);

    // Rocket Inner Core Flame
    final flamePath = Path()
      ..moveTo(256 * scale, 104 * scale)
      ..lineTo(274 * scale, 142 * scale)
      ..lineTo(238 * scale, 142 * scale)
      ..close();
    final flamePaint = Paint()
      ..color = const Color(0xFF00FFF0)
      ..style = PaintingStyle.fill;
    canvas.drawPath(flamePath, flamePaint);

    if (showBadge && size.width >= 56) {
      // BMSTU Text
      final bTextPainter = TextPainter(
        text: TextSpan(
          text: 'BMSTU',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22 * scale,
            fontWeight: FontWeight.w900,
            letterSpacing: 6 * scale,
            fontFamily: 'sans-serif',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      bTextPainter.paint(
        canvas,
        Offset((size.width - bTextPainter.width) / 2 + 3 * scale, 396 * scale),
      );

      // NEO badge
      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width / 2, 442 * scale),
          width: 110 * scale,
          height: 24 * scale,
        ),
        Radius.circular(12 * scale),
      );
      final badgeBgPaint = Paint()
        ..color = const Color(0xFF00D2FF).withValues(alpha: 0.2)
        ..style = PaintingStyle.fill;
      final badgeBorderPaint = Paint()
        ..color = const Color(0xFF00FFF0)
        ..strokeWidth = 1.5 * scale
        ..style = PaintingStyle.stroke;

      canvas.drawRRect(badgeRect, badgeBgPaint);
      canvas.drawRRect(badgeRect, badgeBorderPaint);

      final neoTextPainter = TextPainter(
        text: TextSpan(
          text: 'NEO',
          style: TextStyle(
            color: const Color(0xFF00FFF0),
            fontSize: 12 * scale,
            fontWeight: FontWeight.w800,
            letterSpacing: 4 * scale,
            fontFamily: 'sans-serif',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      neoTextPainter.paint(
        canvas,
        Offset((size.width - neoTextPainter.width) / 2 + 2 * scale, 435 * scale),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BmstuNeoLogoPainter oldDelegate) =>
      oldDelegate.showBadge != showBadge;
}
