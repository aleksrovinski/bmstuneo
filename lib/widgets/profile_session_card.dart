import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/session_result.dart';
import '../providers/auth_provider.dart';
import '../screens/session_screen.dart';
import 'session_grade_badge.dart';

/// Profile summary of the "Сессия" section: the latest semester's results,
/// from the same source (and cache) as [SessionScreen].
class ProfileSessionCard extends StatefulWidget {
  const ProfileSessionCard({super.key});

  @override
  State<ProfileSessionCard> createState() => _ProfileSessionCardState();
}

class _ProfileSessionCardState extends State<ProfileSessionCard> {
  Future<List<SemesterSession>>? _sessions;
  String? _loadedForStage;

  void _loadIfNeeded(AuthProvider auth) {
    if (auth.isGuest || !auth.isFullAuth) return;
    final stage = auth.userProfile?.stageUuid;
    if (_sessions != null && stage == _loadedForStage) return;
    _loadedForStage = stage;
    // Cached results come back immediately; the service refreshes them in the background
    _sessions = auth.apiService.getSessionResults(stageUuid: stage);
  }

  void _openSessionScreen() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SessionScreen()))
        // Pick up what the full screen may have refreshed
        .then((_) {
      if (!mounted) return;
      setState(() => _sessions = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    _loadIfNeeded(auth);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: auth.isGuest || _sessions == null
          ? _buildShell(context, subtitle: 'Доступно после авторизации в ЛКС', enabled: false)
          : FutureBuilder<List<SemesterSession>>(
              future: _sessions,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return _buildShell(context, subtitle: 'Загрузка результатов…', loading: true);
                }
                if (snap.hasError) {
                  return _buildShell(
                    context,
                    subtitle: 'Не удалось загрузить: ${snap.error.toString().replaceAll('Exception: ', '')}',
                  );
                }
                final sessions = snap.data ?? const [];
                if (sessions.isEmpty || sessions.every((s) => s.disciplines.isEmpty)) {
                  return _buildShell(context, subtitle: 'Результатов сессий пока нет');
                }
                // Sessions are sorted newest first
                final latest = sessions.firstWhere((s) => s.disciplines.isNotEmpty);
                return _buildLatest(context, latest, sessions.length);
              },
            ),
    );
  }

  Widget _buildHeader(BuildContext context, {required String subtitle, Color? subtitleColor, bool loading = false}) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.school_rounded, color: theme.colorScheme.onPrimaryContainer, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Результаты сессий',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: subtitleColor ?? theme.colorScheme.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (loading)
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ],
    );
  }

  Widget _buildOpenButton(BuildContext context, {required String label, bool enabled = true}) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: enabled ? _openSessionScreen : null,
        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.primary,
          side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _buildShell(BuildContext context, {required String subtitle, bool loading = false, bool enabled = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, subtitle: subtitle, loading: loading),
        const SizedBox(height: 14),
        _buildOpenButton(context, label: 'Перейти к разделу «Сессия»', enabled: enabled),
      ],
    );
  }

  Widget _buildLatest(BuildContext context, SemesterSession session, int semesterCount) {
    final theme = Theme.of(context);
    final debts = session.debtCount;
    final average = session.averageGrade;
    final total = session.disciplines.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          context,
          subtitle: '${session.semesterTitle} • $total ${disciplinesWord(total)}',
        ),
        const SizedBox(height: 12),
        // One compact summary row; the full table lives in the "Сессия" section
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _stat(context, Icons.check_circle_rounded, 'Сдано ${session.passedCount}/$total', const Color(0xFF16A34A)),
            if (debts > 0)
              _stat(context, Icons.error_rounded, 'Долги: $debts', const Color(0xFFDC2626)),
            if (average != null)
              _stat(context, Icons.star_rounded, 'Ср. балл ${average.toStringAsFixed(2)}', theme.colorScheme.primary),
          ],
        ),
        // Only what needs attention: disciplines with a debt
        if (debts > 0) const SizedBox(height: 8),
        ...session.disciplines.where((d) => d.isDebt).map((d) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: d.title,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
                        ),
                        if (d.controlType.isNotEmpty)
                          TextSpan(
                            text: ' (${d.controlType})',
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Fits "Удовлетворительно" without the fixed table column of the full screen
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 90, maxWidth: 150),
                    child: SessionGradeBadge(discipline: d),
                  ),
                ],
              ),
            )),
        const SizedBox(height: 12),
        _buildOpenButton(
          context,
          label: semesterCount > 1 ? 'Все семестры ($semesterCount)' : 'Перейти к разделу «Сессия»',
        ),
      ],
    );
  }

  Widget _stat(BuildContext context, IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
