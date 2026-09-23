import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:screen_brightness/screen_brightness.dart';

class QrPassDialog extends StatefulWidget {
  final String qrUrl;
  final String studentName;
  final String groupTitle;

  const QrPassDialog({
    super.key,
    required this.qrUrl,
    required this.studentName,
    required this.groupTitle,
  });

  static void show(
    BuildContext context, {
    required String qrUrl,
    required String studentName,
    required String groupTitle,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => QrPassDialog(
        qrUrl: qrUrl,
        studentName: studentName,
        groupTitle: groupTitle,
      ),
    );
  }

  @override
  State<QrPassDialog> createState() => _QrPassDialogState();
}

class _QrPassDialogState extends State<QrPassDialog> {
  bool _brightnessBoosted = false;

  @override
  void initState() {
    super.initState();
    _boostBrightness();
  }

  Future<void> _boostBrightness() async {
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(1.0);
      if (mounted) {
        setState(() => _brightnessBoosted = true);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _restoreBrightness();
    super.dispose();
  }

  Future<void> _restoreBrightness() async {
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.badge_rounded,
                        color: theme.colorScheme.onPrimaryContainer,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Пропуск МГТУ',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // QR Code Container (High contrast white background so optical turnstiles easily scan it)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: widget.qrUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: widget.qrUrl,
                      width: 220,
                      height: 220,
                      fit: BoxFit.contain,
                      placeholder: (context, url) => const SizedBox(
                        width: 220,
                        height: 220,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (context, url, error) => const SizedBox(
                        width: 220,
                        height: 220,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image, size: 40, color: Colors.grey),
                              SizedBox(height: 8),
                              Text(
                                'QR-код не загрузился',
                                style: TextStyle(color: Colors.black54, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(
                      width: 220,
                      height: 220,
                      child: Center(
                        child: Text(
                          'QR пропуск недоступен',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 14),

            // Automatic Brightness Indicator Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.brightness_high_rounded,
                    size: 13,
                    color: Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _brightnessBoosted
                        ? 'Яркость экрана увеличена до максимума'
                        : 'Яркость экрана повышена для сканера',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFD97706),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Student Name & Group
            Text(
              widget.studentName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 3),
            Text(
              'Группа: ${widget.groupTitle}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),

            // Hint
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.qr_code_scanner_rounded,
                    size: 15,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Поднесите к сканеру на турникете',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
