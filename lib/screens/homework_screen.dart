import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/homework_provider.dart';
import '../widgets/homework_sheet.dart';

/// All homework notes: what's left, soonest first, and the recently done ones.
class HomeworkScreen extends StatelessWidget {
  const HomeworkScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HomeworkScreen()));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final homework = context.watch<HomeworkProvider>();
    final pending = homework.pending;
    final done = homework.done;

    return Scaffold(
      appBar: AppBar(title: const Text('Домашние задания')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => HomeworkSheet.show(context),
        tooltip: 'Добавить задание',
        child: const Icon(Icons.add_rounded),
      ),
      body: pending.isEmpty && done.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.task_alt_rounded, size: 48, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
                    const SizedBox(height: 12),
                    const Text('Заданий нет', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      'Запишите, что задали: на следующую пару или к сроку. '
                      'Добавить можно кнопкой + или из карточки пары в расписании.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                for (final note in pending) HomeworkTile(note: note),
                if (done.isNotEmpty)
                  ExpansionTile(
                    title: Text('Выполненные (${done.length})'),
                    children: [for (final note in done) HomeworkTile(note: note)],
                  ),
              ],
            ),
    );
  }
}
