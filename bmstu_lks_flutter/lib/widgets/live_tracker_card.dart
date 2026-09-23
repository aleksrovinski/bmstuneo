import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/schedule_provider.dart';
import 'live_activity_settings_sheet.dart';

class LiveTrackerCard extends StatefulWidget {
  const LiveTrackerCard({super.key});

  @override
  State<LiveTrackerCard> createState() => _LiveTrackerCardState();
}

class _LiveTrackerCardState extends State<LiveTrackerCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Isolated 1-second ticker specifically for the countdown text
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sched = context.watch<ScheduleProvider>();
    final status = sched.getLivePairStatus();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color cardColor;
    Color accentColor;
    IconData icon;

    switch (status.type) {
      case LivePairType.inProgress:
        cardColor = theme.colorScheme.primaryContainer;
        accentColor = theme.colorScheme.onPrimaryContainer;
        icon = Icons.play_circle_fill_rounded;
        break;
      case LivePairType.upcoming:
        cardColor = isDark
            ? theme.colorScheme.surfaceContainer
            : theme.colorScheme.surfaceContainerLow;
        accentColor = theme.colorScheme.primary;
        icon = Icons.alarm_rounded;
        break;
      default:
        cardColor = isDark
            ? theme.colorScheme.surfaceContainer
            : theme.colorScheme.surfaceContainerLow;
        accentColor = theme.colorScheme.tertiary;
        icon = Icons.check_circle_outline_rounded;
        break;
    }

    final isInProgress = status.type == LivePairType.inProgress;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: isInProgress
            ? null
            : Border.all(
                color: theme.colorScheme.outlineVariant,
              ),
        boxShadow: [
          BoxShadow(
            color: isInProgress
                ? theme.colorScheme.primary.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => LiveActivitySettingsSheet.show(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isInProgress
                        ? theme.colorScheme.primary.withValues(alpha: 0.2)
                        : accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: isInProgress
                        ? theme.colorScheme.onPrimaryContainer
                        : accentColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status.headline,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isInProgress
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        status.subline,
                        style: TextStyle(
                          fontSize: 12,
                          color: isInProgress
                              ? theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.85)
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: isInProgress
                        ? theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  tooltip: 'Live Activity и виджет',
                  onPressed: () => LiveActivitySettingsSheet.show(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
