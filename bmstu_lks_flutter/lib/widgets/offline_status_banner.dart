import 'package:flutter/material.dart';

class OfflineStatusBanner extends StatelessWidget {
  final String? message;
  final DateTime? lastUpdated;
  final VoidCallback? onRetry;

  const OfflineStatusBanner({
    super.key,
    this.message,
    this.lastUpdated,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bannerText = message?.isNotEmpty == true
        ? message!
        : 'Офлайн-режим (сохранённая копия)';

    String? timeStr;
    if (lastUpdated != null) {
      final dt = lastUpdated!;
      final minStr = dt.minute.toString().padLeft(2, '0');
      final hourStr = dt.hour.toString().padLeft(2, '0');
      timeStr = '${dt.day}.${dt.month.toString().padLeft(2, '0')} в $hourStr:$minStr';
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)
            : colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  bannerText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (timeStr != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Данные от $timeStr',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              onPressed: onRetry,
              tooltip: 'Повторить попытку',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              color: colorScheme.primary,
            ),
          ],
        ],
      ),
    );
  }
}
