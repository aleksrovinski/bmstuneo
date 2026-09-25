import 'package:flutter/material.dart';

/// The official BMSTU neo app icon & brand logo widget.
/// Displays the desktop launcher icon (stylized "Б" with cyan spark on blue gradient).
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
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0070F3).withValues(alpha: 0.35),
            blurRadius: size * 0.22,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      child: Image.asset(
        'assets/icons/app_icon_512.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
