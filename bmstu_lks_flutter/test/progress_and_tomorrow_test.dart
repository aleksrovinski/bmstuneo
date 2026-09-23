import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bmstu_neo/models/discipline_progress.dart';
import 'package:bmstu_neo/providers/schedule_provider.dart';
import 'package:bmstu_neo/providers/progress_provider.dart';
import 'package:bmstu_neo/services/bmstu_api_service.dart';
import 'package:bmstu_neo/services/widget_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('ControlEvent & DisciplineProgress Models', () {
    test('ControlEvent correctly separates issued (stage 1) from submitted (stage 2/3) and not-issued', () {
      // 1. Issued Homework (Выдано, stage 1)
      final hw = ControlEvent(
        type: 'ДЗ',
        title: 'ДЗ-1',
        week: 5,
        stage: '1',
        passStatus: 'early',
        disciplineTitle: 'Кратные интегралы',
        controlIndex: 1,
      );
      expect(hw.statusTitle, 'Выдано');
      expect(hw.isIssued, isTrue, reason: 'Stage 1 must be issued');
      expect(hw.isSubmitted, isFalse, reason: 'Issued task must NOT be marked as submitted');
      expect(hw.isNotIssued, isFalse);
      expect(hw.shortBadgeText, 'Выдано');
      expect(hw.statusIcon, Icons.edit_note_rounded);
      expect(hw.statusColor, const Color(0xFF0070F3));
      expect(hw.eventState, EventState.issued);

      // 2. Scheduled Control Work (РК stage 1: Назначен, NOT Выдано!)
      final rkScheduled = ControlEvent(
        type: 'РК',
        title: 'РК-1',
        week: 7,
        stage: '1',
        disciplineTitle: 'Физика',
        controlIndex: 1,
      );
      expect(rkScheduled.isIssued, isTrue);
      expect(rkScheduled.isSubmitted, isFalse);
      expect(rkScheduled.shortBadgeText, 'Назначен');
      expect(rkScheduled.shortBadgeText, isNot('Выдано'), reason: 'РК CANNOT be Выдано!');
      expect(rkScheduled.statusTitle, 'Назначен (предстоит)');
      expect(rkScheduled.statusIcon, Icons.assignment_late_rounded);
      expect(rkScheduled.statusColor, const Color(0xFF2563EB));

      // 3. Submitted Control Work (РК stage 3: Сдано / Зачтено)
      final rk = ControlEvent(
        type: 'РК',
        title: 'РК-1',
        week: 5,
        stage: '3',
        passStatus: 'early',
        disciplineTitle: 'Физика',
        controlIndex: 1,
        setDate: '2026-09-08 12:22:25',
      );
      expect(rk.statusTitle, 'Сдано / Зачтено');
      expect(rk.passStatusTitle, 'раньше срока');
      expect(rk.isSubmitted, isTrue);
      expect(rk.isIssued, isFalse);
      expect(rk.isNotIssued, isFalse);
      expect(rk.shortBadgeText, 'Сдано');
      expect(rk.statusIcon, Icons.check_circle_rounded);
      expect(rk.statusColor, const Color(0xFF10B981));
      expect(rk.eventState, EventState.submitted);

      // 4. Completed Homework (Выполнено, stage 2)
      final hwDone = ControlEvent(
        type: 'ДЗ',
        title: 'ДЗ-2',
        week: 6,
        stage: '2',
        passStatus: 'in-time',
        disciplineTitle: 'Физика',
        controlIndex: 2,
      );
      expect(hwDone.isSubmitted, isTrue);
      expect(hwDone.isIssued, isFalse);
      expect(hwDone.statusTitle, 'Выполнено');
      expect(hwDone.shortBadgeText, 'Выполнено');
      expect(hwDone.statusColor, const Color(0xFF10B981));

      // 5. Not yet issued Future Task (Не выдано, stage null)
      final planned = ControlEvent(
        type: 'ДЗ',
        title: 'ДЗ-3',
        week: 8,
        stage: null,
        disciplineTitle: 'Инженерная графика',
        controlIndex: 3,
      );
      expect(planned.isNotIssued, isTrue);
      expect(planned.isIssued, isFalse);
      expect(planned.isSubmitted, isFalse);
      expect(planned.shortBadgeText, 'Не выдано');
      expect(planned.statusIcon, Icons.schedule_rounded);
      expect(planned.statusColor, const Color(0xFF64748B));
      expect(planned.eventState, EventState.notIssued);

      // 6. Seminars
      final sem = ControlEvent(
        type: 'СЗ',
        title: 'Семинар 1',
        week: 1,
        stage: '4',
        disciplineTitle: 'Политология',
        controlIndex: 1,
      );
      expect(sem.statusTitle, 'Посещено');
      expect(sem.isSubmitted, isTrue);
      expect(sem.statusIcon, Icons.check_circle_rounded);
      expect(sem.statusColor, const Color(0xFF10B981));

      final semMissed = ControlEvent(
        type: 'СЗ',
        title: 'Семинар 2',
        week: 2,
        stage: '0',
        disciplineTitle: 'Политология',
        controlIndex: 2,
      );
      expect(semMissed.statusTitle, 'Пропущено');
      expect(semMissed.isMissed, isTrue);
      expect(semMissed.isSubmitted, isFalse);
      expect(semMissed.statusIcon, Icons.cancel_rounded);
      expect(semMissed.statusColor, const Color(0xFFEF4444));

      // 7. Modules
      final module = ControlEvent(
        type: 'М',
        title: 'Модуль 1',
        week: 10,
        value: '6',
        stage: '13',
        points: {
          'point_3': '36',
          'point_4': '42',
          'point_5': '51',
          'point_all': '60',
        },
        disciplineTitle: 'ФКиС',
        controlIndex: 1,
      );
      expect(module.statusTitle, 'Зачтен (6 б.)');
      expect(module.isSubmitted, isTrue);
      expect(module.value, '6');
      expect(module.points!['point_all'], '60');
      expect(module.statusIcon, Icons.check_circle_rounded);
      expect(module.statusColor, const Color(0xFF10B981));
    });

    test('DisciplineProgress separates controls, labs and seminars', () {
      final disc = DisciplineProgress(
        title: 'Физика',
        points: {'point_all': '100'},
        controls: [
          ControlEvent(
            type: 'РК',
            title: 'РК-1',
            week: 8,
            stage: '1',
            disciplineTitle: 'Физика',
            controlIndex: 1,
          ),
        ],
        laboratory: [
          ControlEvent(
            type: 'ЛР',
            title: 'ЛР-1',
            week: 2,
            stage: '2',
            disciplineTitle: 'Физика',
            controlIndex: 1,
          ),
        ],
        seminars: [
          ControlEvent(
            type: 'СЗ',
            title: 'СЗ-1',
            week: 1,
            stage: '4',
            disciplineTitle: 'Физика',
            controlIndex: 1,
          ),
        ],
      );

      expect(disc.hasControls, isTrue);
      expect(disc.hasLaboratory, isTrue);
      expect(disc.hasSeminars, isTrue);
      expect(disc.currentPointsSummary, 'Макс: 100 б.');
    });
  });

  group('Tomorrow Schedule Logic in ScheduleProvider', () {
    test('Calculates tomorrow day title and weekday', () {
      final provider = ScheduleProvider(apiService: BmstuApiService());
      expect(provider.tomorrowWeekday, isIn([1, 2, 3, 4, 5, 6, 7]));
      expect(provider.tomorrowDayTitle, isNotEmpty);
    });
  });

  group('ProgressProvider Categories & Filtering', () {
    test('Filters disciplines based on active category and status filter', () {
      final provider = ProgressProvider(apiService: BmstuApiService());
      expect(provider.activeCategory, ProgressCategory.controls);
      expect(provider.statusFilter, ProgressStatusFilter.all);

      provider.setActiveCategory(ProgressCategory.laboratory);
      expect(provider.activeCategory, ProgressCategory.laboratory);

      provider.setStatusFilter(ProgressStatusFilter.issued);
      expect(provider.statusFilter, ProgressStatusFilter.issued);

      provider.setStatusFilter(ProgressStatusFilter.submitted);
      expect(provider.statusFilter, ProgressStatusFilter.submitted);

      provider.setStatusFilter(ProgressStatusFilter.notIssued);
      expect(provider.statusFilter, ProgressStatusFilter.notIssued);
    });
  });

  group('WidgetSyncService', () {
    test('Safely handles non-Android environment and updates without error', () async {
      final isSupported = await WidgetSyncService.isPinningSupported();
      // On non-Android (desktop test environment), pinning is false
      expect(isSupported, isFalse);

      final provider = ScheduleProvider(apiService: BmstuApiService());
      // Calling updateScheduleWidget on non-Android returns safely
      await expectLater(
        WidgetSyncService.updateScheduleWidget(scheduleProvider: provider),
        completes,
      );
    });
  });
}
