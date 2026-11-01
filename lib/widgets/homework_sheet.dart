import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/homework_note.dart';
import '../providers/homework_provider.dart';
import '../providers/schedule_provider.dart';

const _months = ['янв.', 'февр.', 'марта', 'апр.', 'мая', 'июня', 'июля', 'авг.', 'сент.', 'окт.', 'нояб.', 'дек.'];
const _weekdays = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];

String _two(int v) => v.toString().padLeft(2, '0');

/// "сегодня", "завтра" or "чт, 6 нояб." for [date] as seen at [now].
String homeworkDay(DateTime date, DateTime now) {
  final days = DateTime(date.year, date.month, date.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (days == 0) return 'сегодня';
  if (days == 1) return 'завтра';
  if (days == -1) return 'вчера';
  return '${_weekdays[date.weekday - 1]}, ${date.day} ${_months[date.month - 1]}';
}

/// When the homework is due, as shown under the note.
String homeworkDueLabel(HomeworkNote note, DateTime now) {
  final day = homeworkDay(note.due, now);
  if (note.isOverdue(now)) return 'Просрочено · $day';
  if (note.kind == HomeworkKind.quick) return 'К паре · $day, ${_two(note.due.hour)}:${_two(note.due.minute)}';
  return 'Срок · $day';
}

/// Bottom sheet to add or edit a homework note.
class HomeworkSheet extends StatefulWidget {
  final String? disciplineTitle;
  final HomeworkNote? existing;

  const HomeworkSheet({super.key, this.disciplineTitle, this.existing});

  static Future<void> show(BuildContext context, {String? disciplineTitle, HomeworkNote? existing}) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => HomeworkSheet(disciplineTitle: disciplineTitle, existing: existing),
      );

  @override
  State<HomeworkSheet> createState() => _HomeworkSheetState();
}

class _HomeworkSheetState extends State<HomeworkSheet> {
  late final TextEditingController _text;
  String? _discipline;
  late HomeworkKind _kind;
  DateTime? _deadline;

  @override
  void initState() {
    super.initState();
    final note = widget.existing;
    _text = TextEditingController(text: note?.text ?? '');
    _discipline = note?.disciplineTitle ?? widget.disciplineTitle;
    _kind = note?.kind ?? HomeworkKind.quick;
    if (note?.kind == HomeworkKind.long) _deadline = note!.due;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  ({DateTime start, String where})? _nextPair(ScheduleProvider sched) {
    final discipline = _discipline;
    if (discipline == null) return null;
    final next = nextPairOf(
      discipline,
      sched.allLessons,
      currentWeekIsNumerator: sched.currentWeek?.isNumerator ?? true,
      now: DateTime.now(),
    );
    if (next == null) return null;
    return (start: next.start, where: '${next.lesson.actTypeTitle}, ${next.lesson.audiencesFormatted}');
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Срок сдачи',
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _save(DateTime due) async {
    final homework = context.read<HomeworkProvider>();
    final existing = widget.existing;
    if (existing != null) {
      await homework.update(existing.copyWith(text: _text.text.trim(), kind: _kind, due: due));
    } else {
      await homework.add(disciplineTitle: _discipline!, text: _text.text, kind: _kind, due: due);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sched = context.watch<ScheduleProvider>();
    final now = DateTime.now();

    final disciplines = {for (final l in sched.allLessons) l.disciplineTitle}.toList()..sort();
    if (_discipline != null && !disciplines.contains(_discipline)) disciplines.insert(0, _discipline!);

    final next = _kind == HomeworkKind.quick ? _nextPair(sched) : null;
    // Long homework is due by the end of the chosen day
    final DateTime? due = _kind == HomeworkKind.quick
        ? next?.start
        : (_deadline == null ? null : DateTime(_deadline!.year, _deadline!.month, _deadline!.day, 23, 59));
    final canSave = _discipline != null && _text.text.trim().isNotEmpty && due != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? 'Новое домашнее задание' : 'Домашнее задание',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (widget.existing != null || widget.disciplineTitle != null)
              Text(_discipline!, style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary))
            else
              DropdownButtonFormField<String>(
                initialValue: _discipline,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Предмет', border: OutlineInputBorder()),
                items: [
                  for (final d in disciplines) DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _discipline = v),
              ),
            const SizedBox(height: 16),
            SegmentedButton<HomeworkKind>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: HomeworkKind.quick,
                  icon: Icon(Icons.bolt_rounded, size: 18),
                  label: Text('К след. паре'),
                ),
                ButtonSegment(
                  value: HomeworkKind.long,
                  icon: Icon(Icons.event_rounded, size: 18),
                  label: Text('К сроку'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 12),
            if (_kind == HomeworkKind.quick)
              _DueRow(
                icon: Icons.schedule_rounded,
                text: _discipline == null
                    ? 'Выберите предмет, чтобы найти следующую пару'
                    : next == null
                        ? 'Пар по этому предмету в расписании нет — укажите срок'
                        : 'К паре ${homeworkDay(next.start, now)}, ${_two(next.start.hour)}:${_two(next.start.minute)} · ${next.where}',
              )
            else
              OutlinedButton.icon(
                onPressed: _pickDeadline,
                icon: const Icon(Icons.calendar_month_rounded),
                label: Text(_deadline == null ? 'Выбрать срок' : 'Срок: ${homeworkDay(_deadline!, now)}'),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _text,
              autofocus: widget.existing == null,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Что задали',
                hintText: 'Например: № 4.12–4.18, повторить формулы Грина',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: canSave ? () => _save(due) : null,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DueRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _DueRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: scheme.onSurface))),
        ],
      ),
    );
  }
}

/// One homework note: tick to mark done, tap to edit, swipe to delete (with undo).
class HomeworkTile extends StatelessWidget {
  final HomeworkNote note;
  final bool showDiscipline;

  const HomeworkTile({super.key, required this.note, this.showDiscipline = true});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final homework = context.read<HomeworkProvider>();
    final now = DateTime.now();
    final overdue = note.isOverdue(now);

    return Dismissible(
      key: ValueKey('homework-${note.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: scheme.errorContainer,
        child: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) {
        homework.remove(note);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Задание удалено'),
          action: SnackBarAction(label: 'Вернуть', onPressed: () => homework.restore(note)),
        ));
      },
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 4, right: 16),
        leading: Checkbox(
          value: note.done,
          onChanged: (v) => homework.setDone(note, v ?? false),
          semanticLabel: note.done ? 'Отметить как невыполненное' : 'Отметить как выполненное',
        ),
        title: Text(
          note.text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            decoration: note.done ? TextDecoration.lineThrough : null,
            color: note.done ? scheme.onSurfaceVariant : scheme.onSurface,
          ),
        ),
        subtitle: Text(
          [homeworkDueLabel(note, now), if (showDiscipline) note.disciplineTitle].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: overdue ? scheme.error : scheme.onSurfaceVariant),
        ),
        trailing: Icon(
          note.kind == HomeworkKind.quick ? Icons.bolt_rounded : Icons.event_rounded,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
        onTap: () => HomeworkSheet.show(context, existing: note),
      ),
    );
  }
}
