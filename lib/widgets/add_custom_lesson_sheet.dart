import 'package:flutter/material.dart';
import '../models/schedule_lesson.dart';

class AddCustomLessonSheet extends StatefulWidget {
  final int initialDay;

  const AddCustomLessonSheet({
    super.key,
    required this.initialDay,
  });

  static Future<ScheduleLesson?> show(BuildContext context, {int initialDay = 1}) {
    return showModalBottomSheet<ScheduleLesson>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddCustomLessonSheet(initialDay: initialDay),
    );
  }

  @override
  State<AddCustomLessonSheet> createState() => _AddCustomLessonSheetState();
}

class _AddCustomLessonSheetState extends State<AddCustomLessonSheet> {
  final _titleController = TextEditingController();
  final _roomController = TextEditingController();
  final _teacherController = TextEditingController();

  late int _selectedDay;
  int _selectedPair = 1;
  bool _isCustomTime = false;
  TimeOfDay _customStartTime = const TimeOfDay(hour: 10, minute: 15);
  TimeOfDay _customEndTime = const TimeOfDay(hour: 11, minute: 50);
  String _selectedActType = 'seminar';
  String _selectedWeek = 'all';

  static const List<Map<String, String>> _pairTimes = [
    {'start': '08:30', 'end': '10:05'},
    {'start': '10:15', 'end': '11:50'},
    {'start': '12:00', 'end': '13:35'},
    {'start': '13:50', 'end': '15:25'},
    {'start': '15:40', 'end': '17:15'},
    {'start': '17:25', 'end': '19:00'},
    {'start': '19:10', 'end': '20:45'},
  ];

  static const List<String> _daysShort = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];

  @override
  void initState() {
    super.initState();
    _selectedDay = widget.initialDay.clamp(1, 7);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _roomController.dispose();
    _teacherController.dispose();
    super.dispose();
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Введите название предмета или занятия'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final String startStr;
    final String endStr;
    final int pairNumber;

    if (_isCustomTime) {
      final startTotal = _customStartTime.hour * 60 + _customStartTime.minute;
      final endTotal = _customEndTime.hour * 60 + _customEndTime.minute;
      if (endTotal <= startTotal) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Время окончания должно быть позже времени начала'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }

      startStr = _formatTime(_customStartTime);
      endStr = _formatTime(_customEndTime);

      // Determine closest pair slot or set 0
      int closest = 0;
      for (int i = 0; i < _pairTimes.length; i++) {
        final pts = _pairTimes[i]['start']!.split(':');
        final pte = _pairTimes[i]['end']!.split(':');
        final pStartMin = int.parse(pts[0]) * 60 + int.parse(pts[1]);
        final pEndMin = int.parse(pte[0]) * 60 + int.parse(pte[1]);
        if (startTotal >= pStartMin - 15 && startTotal <= pEndMin) {
          closest = i + 1;
          break;
        }
      }
      pairNumber = closest;
    } else {
      final pairIndex = (_selectedPair - 1).clamp(0, _pairTimes.length - 1);
      final times = _pairTimes[pairIndex];
      startStr = times['start']!;
      endStr = times['end']!;
      pairNumber = _selectedPair;
    }

    final roomText = _roomController.text.trim();
    final teacherText = _teacherController.text.trim();

    final lesson = ScheduleLesson(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      isCustom: true,
      day: _selectedDay,
      time: pairNumber,
      startTime: startStr,
      endTime: endStr,
      week: _selectedWeek,
      disciplineTitle: title,
      actType: _selectedActType,
      audiences: roomText.isNotEmpty
          ? [ScheduleAudience(name: roomText)]
          : [],
      teachers: teacherText.isNotEmpty
          ? [
              ScheduleTeacher(
                firstName: '',
                lastName: teacherText,
                middleName: '',
              )
            ]
          : [],
    );

    Navigator.of(context).pop(lesson);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.edit_calendar_rounded,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Добавить своё занятие',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // 1. Discipline Name
            Text(
              'Название предмета *',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Например: Военная кафедра / Английский язык',
                filled: true,
                fillColor: isDark
                    ? theme.colorScheme.surfaceContainer
                    : theme.colorScheme.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 2. Day of week selector
            Text(
              'День недели',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: List.generate(7, (idx) {
                final day = idx + 1;
                final isSelected = day == _selectedDay;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedDay = day),
                    child: Container(
                      margin: EdgeInsets.only(right: idx < 6 ? 5 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : (isDark
                                ? theme.colorScheme.surfaceContainer
                                : theme.colorScheme.surface),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _daysShort[idx],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 14),

            // 3. Pair Slot (1 to 7 or Custom time)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Время занятия',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _isCustomTime = !_isCustomTime),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _isCustomTime
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isCustomTime ? Icons.tune_rounded : Icons.more_time_rounded,
                          size: 14,
                          color: _isCustomTime
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isCustomTime ? 'Выбрать пару' : 'Своё время',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _isCustomTime
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (!_isCustomTime) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ...List.generate(_pairTimes.length, (idx) {
                      final pairNum = idx + 1;
                      final isSelected = pairNum == _selectedPair;
                      final time = _pairTimes[idx];

                      return GestureDetector(
                        onTap: () => setState(() => _selectedPair = pairNum),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : (isDark
                                    ? theme.colorScheme.surfaceContainer
                                    : theme.colorScheme.surface),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$pairNum пара',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? theme.colorScheme.onPrimary
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                '${time['start']}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isSelected
                                      ? theme.colorScheme.onPrimary
                                          .withValues(alpha: 0.85)
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    // Button to switch to custom time
                    GestureDetector(
                      onTap: () => setState(() => _isCustomTime = true),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? theme.colorScheme.surfaceContainer
                              : theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.more_time_rounded,
                                size: 14, color: theme.colorScheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              'Своё время',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Custom time pickers for Start and End time
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _customStartTime,
                          helpText: 'Время начала занятия',
                        );
                        if (picked != null) {
                          setState(() {
                            _customStartTime = picked;
                            final startTotal = picked.hour * 60 + picked.minute;
                            final endTotal = _customEndTime.hour * 60 + _customEndTime.minute;
                            if (endTotal <= startTotal) {
                              final newEndTotal = (startTotal + 95) % (24 * 60);
                              _customEndTime = TimeOfDay(
                                hour: newEndTotal ~/ 60,
                                minute: newEndTotal % 60,
                              );
                            }
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? theme.colorScheme.surfaceContainer
                              : theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(alpha: 0.6),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Начало',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(Icons.access_time_rounded,
                                    size: 16, color: theme.colorScheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  _formatTime(_customStartTime),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _customEndTime,
                          helpText: 'Время окончания занятия',
                        );
                        if (picked != null) {
                          setState(() => _customEndTime = picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? theme.colorScheme.surfaceContainer
                              : theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(alpha: 0.6),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Окончание',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(Icons.schedule_rounded,
                                    size: 16, color: theme.colorScheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  _formatTime(_customEndTime),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),

            // 4. Act Type (Тип занятия)
            Text(
              'Тип занятия',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildActTypeChip('Семинар', 'seminar'),
                _buildActTypeChip('Лекция', 'lecture'),
                _buildActTypeChip('Лабораторная', 'lab'),
                _buildActTypeChip('Военная кафедра', 'military'),
                _buildActTypeChip('Факультатив', 'elective'),
                _buildActTypeChip('Консультация', 'consultation'),
              ],
            ),
            const SizedBox(height: 14),

            // 5. Week parity (Числ. / Знам. / Все)
            Text(
              'Периодичность',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('Все недели')),
                ButtonSegment(value: 'ch', label: Text('Числитель')),
                ButtonSegment(value: 'zn', label: Text('Знаменатель')),
              ],
              selected: {_selectedWeek},
              onSelectionChanged: (set) {
                setState(() => _selectedWeek = set.first);
              },
            ),
            const SizedBox(height: 14),

            // 6. Audience and Teacher
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Аудитория',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _roomController,
                        decoration: InputDecoration(
                          hintText: '323 (ГУК)',
                          filled: true,
                          fillColor: isDark
                              ? theme.colorScheme.surfaceContainer
                              : theme.colorScheme.surface,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: theme.colorScheme.outlineVariant),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Преподаватель',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _teacherController,
                        decoration: InputDecoration(
                          hintText: 'Фамилия И.О.',
                          filled: true,
                          fillColor: isDark
                              ? theme.colorScheme.surfaceContainer
                              : theme.colorScheme.surface,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: theme.colorScheme.outlineVariant),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check_rounded, size: 20),
                label: const Text(
                  'Добавить занятие',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActTypeChip(String label, String value) {
    final theme = Theme.of(context);
    final isSelected = _selectedActType == value;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _selectedActType = value);
      },
      selectedColor: theme.colorScheme.primaryContainer,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurface,
      ),
    );
  }
}
