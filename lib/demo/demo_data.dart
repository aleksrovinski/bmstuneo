import '../models/current_week.dart';
import '../models/discipline_progress.dart';
import '../models/homework_note.dart';
import '../models/physical_culture.dart';
import '../models/schedule_lesson.dart';
import '../models/session_result.dart';
import '../models/user_profile.dart';

/// Sample data for the demo build: a made-up student whose week shows every
/// feature. Dates are relative to [now], so the demo always has a pair in progress
/// during the day, deadlines this week and scores for past modules.
class DemoData {
  final DateTime now;
  DemoData([DateTime? now]) : now = now ?? DateTime.now();

  static const groupUuid = 'demo-group-rk6-31b';
  static const stageUuid = 'demo-stage-3';

  CurrentWeek get week => CurrentWeek.defaultWeek(now);

  UserProfile get profile => UserProfile(
        lastName: 'Иванов',
        firstName: 'Алексей',
        middleName: 'Сергеевич',
        groupTitle: 'РК6-31Б',
        groupCode: 'РК6-31Б',
        groupUuid: groupUuid,
        stageUuid: stageUuid,
        cardNumber: '24Р0137',
        semester: 3,
        specialityTitle: '09.03.01 Информатика и вычислительная техника',
        specializationTitle: 'Системы автоматизированного проектирования',
        studyType: 'Бюджетная основа',
        state: 'Обучается',
        hasDormitory: true,
        birthDate: '14.03.2006',
      );

  // ---------------------------------------------------------------------------
  // Schedule

  static const _slots = [
    ('08:30', '10:05'),
    ('10:15', '11:50'),
    ('12:00', '13:35'),
    ('13:50', '15:25'),
    ('15:40', '17:15'),
    ('17:25', '19:00'),
    ('19:10', '20:45'),
  ];

  static final _teachers = {
    'matan': ScheduleTeacher(lastName: 'Соколова', firstName: 'Марина', middleName: 'Андреевна', uuid: 'demo-t-sokolova'),
    'physics': ScheduleTeacher(lastName: 'Голубев', firstName: 'Игорь', middleName: 'Петрович', uuid: 'demo-t-golubev'),
    'physicsLab': ScheduleTeacher(lastName: 'Лукина', firstName: 'Ксения', middleName: 'Борисовна', uuid: 'demo-t-lukina'),
    'prog': ScheduleTeacher(lastName: 'Орлов', firstName: 'Дмитрий', middleName: 'Олегович', uuid: 'demo-t-orlov'),
    'graphics': ScheduleTeacher(lastName: 'Белова', firstName: 'Анна', middleName: 'Викторовна', uuid: 'demo-t-belova'),
    'english': ScheduleTeacher(lastName: 'Миронова', firstName: 'Ольга', middleName: 'Игоревна', uuid: 'demo-t-mironova'),
    'materials': ScheduleTeacher(lastName: 'Карпов', firstName: 'Сергей', middleName: 'Николаевич', uuid: 'demo-t-karpov'),
    'history': ScheduleTeacher(lastName: 'Зайцева', firstName: 'Елена', middleName: 'Павловна', uuid: 'demo-t-zaitseva'),
  };

  static List<ScheduleTeacher> get teachers => _teachers.values.toList();

  ScheduleLesson _lesson(
    int day,
    int slot,
    String title,
    String type,
    String room,
    String building,
    String? teacher, {
    String week = 'all',
    String? stream,
    String? start,
    String? end,
  }) =>
      ScheduleLesson(
        id: 'demo-$day-$slot-$week',
        day: day,
        time: slot,
        startTime: start ?? _slots[slot - 1].$1,
        endTime: end ?? _slots[slot - 1].$2,
        week: week,
        disciplineTitle: title,
        actType: type,
        audiences: [ScheduleAudience(name: room, building: building)],
        teachers: teacher == null ? const [] : [_teachers[teacher]!],
        streamName: stream,
        isStream: stream != null,
      );

  /// A regular week, then today replaced by pairs placed around the current time.
  List<ScheduleLesson> get schedule {
    const stream = 'РК6-31Б; РК6-32Б; РК6-33Б; РК6-34Б';
    final week = <ScheduleLesson>[
      _lesson(1, 1, 'Математический анализ', 'lecture', '218л', 'УЛК', 'matan', stream: stream),
      _lesson(1, 2, 'Математический анализ', 'seminar', '532', 'ГУК', 'matan'),
      _lesson(1, 3, 'Иностранный язык', 'seminar', '1018л', 'УЛК', 'english'),
      _lesson(2, 2, 'Физика', 'lecture', '323', 'ГУК', 'physics', stream: stream),
      _lesson(2, 3, 'Физика', 'lab', 'каф. ФН4', 'Кафедра ФН', 'physicsLab', week: 'ch'),
      _lesson(2, 3, 'Инженерная графика', 'seminar', '427', 'ГУК', 'graphics', week: 'zn'),
      _lesson(2, 4, 'Элективный курс по физической культуре и спорту', 'seminar', 'каф. ФВ', 'Спорткомплекс', null),
      _lesson(3, 1, 'Программирование на C++', 'lecture', '501ю', 'ГУК', 'prog', stream: stream),
      _lesson(3, 2, 'Программирование на C++', 'lab', '806л', 'УЛК', 'prog'),
      _lesson(3, 3, 'История России', 'lecture', '224л', 'УЛК', 'history', week: 'ch'),
      _lesson(4, 2, 'Материаловедение', 'lecture', '220л', 'УЛК', 'materials'),
      _lesson(4, 3, 'Материаловедение', 'lab', '120', 'Корпус Э', 'materials', week: 'zn'),
      _lesson(4, 4, 'Инженерная графика', 'seminar', '427', 'ГУК', 'graphics'),
      _lesson(5, 1, 'Математический анализ', 'seminar', '532', 'ГУК', 'matan'),
      _lesson(5, 2, 'Физика', 'seminar', '318', 'ГУК', 'physics'),
      _lesson(5, 3, 'Консультация по физике', 'consultation', '318', 'ГУК', 'physics', week: 'zn'),
      _lesson(6, 2, 'Элективный курс по физической культуре и спорту', 'seminar', 'каф. ФВ', 'Спорткомплекс', null),
    ];

    final today = now.weekday;
    if (today == DateTime.sunday) return week;
    return [...week.where((l) => l.day != today), ..._liveToday(today)];
  }

  /// One pair already over, one in progress (started half an hour ago) and one next,
  /// so the home card, Live Update and widget all have something to show.
  List<ScheduleLesson> _liveToday(int day) {
    String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final start = DateTime(now.year, now.month, now.day, now.hour, now.minute - now.minute % 5)
        .subtract(const Duration(minutes: 30));
    const pair = Duration(minutes: 95);
    const gap = Duration(minutes: 15);
    final earlier = start.subtract(pair + gap);
    final next = start.add(pair + gap);
    // Keep the day in one calendar day: late at night the live pairs would wrap around
    if (earlier.day != now.day || next.add(pair).day != now.day) {
      return [
        _lesson(day, 2, 'Программирование на C++', 'lecture', '501ю', 'ГУК', 'prog'),
        _lesson(day, 3, 'Математический анализ', 'seminar', '532', 'ГУК', 'matan'),
      ];
    }
    return [
      _lesson(day, 2, 'Иностранный язык', 'seminar', '1018л', 'УЛК', 'english',
          start: hm(earlier), end: hm(earlier.add(pair))),
      _lesson(day, 3, 'Программирование на C++', 'lecture', '501ю', 'ГУК', 'prog',
          start: hm(start), end: hm(start.add(pair))),
      _lesson(day, 4, 'Математический анализ', 'seminar', '532', 'ГУК', 'matan',
          start: hm(next), end: hm(next.add(pair))),
    ];
  }

  List<ScheduleLesson> scheduleOfTeacher(String teacherUuid) =>
      schedule.where((l) => l.teachers.any((t) => t.uuid == teacherUuid)).toList();

  // ---------------------------------------------------------------------------
  // Progress (БРС)

  static const _module = {'point_3': '19', 'point_4': '23', 'point_5': '28', 'point_all': '33'};

  List<DisciplineProgress> get progress {
    final w = week.weekNumber;
    int at(int offset) => (w + offset).clamp(1, 17);

    ControlEvent ev(String discipline, String type, int index, int weekOffset,
            {String? stage, Object? value, bool module = false}) =>
        ControlEvent(
          type: type,
          title: type == 'М' ? 'Модуль $index' : '$type-$index',
          week: at(weekOffset),
          stage: stage,
          value: value,
          points: module ? _module : null,
          disciplineTitle: discipline,
          controlIndex: index,
          controlId: 'demo-$discipline-$type-$index',
        );

    DisciplineProgress d(String title, List<ControlEvent> controls,
            {List<ControlEvent> labs = const [], List<ControlEvent> seminars = const []}) =>
        DisciplineProgress(
          title: title,
          disciplineUuid: 'demo-$title',
          points: const {'point_all': '100'},
          controls: controls,
          laboratory: labs,
          seminars: seminars,
        );

    const matan = 'Математический анализ';
    const physics = 'Физика';
    const prog = 'Программирование на C++';
    const graphics = 'Инженерная графика';
    const materials = 'Материаловедение';
    const english = 'Иностранный язык';

    return [
      d(matan, [
        ev(matan, 'ДЗ', 1, -4, stage: '3'),
        ev(matan, 'РК', 1, -3, stage: '3', value: '18'),
        ev(matan, 'М', 1, -3, stage: '13', value: '27', module: true),
        ev(matan, 'ДЗ', 2, 0, stage: '1'),
        ev(matan, 'РК', 2, 2),
        ev(matan, 'М', 2, 6, module: true),
      ], seminars: [
        ev(matan, 'СЗ', 1, -3, stage: '4'),
        ev(matan, 'СЗ', 2, -2, stage: '12'),
        ev(matan, 'СЗ', 3, -1, stage: '0'),
        ev(matan, 'СЗ', 4, 0, stage: '4'),
      ]),
      d(physics, [
        ev(physics, 'ДЗ', 1, -2, stage: '3'),
        ev(physics, 'М', 1, -2, stage: '13', value: '21', module: true),
        ev(physics, 'РК', 2, 1, stage: '1'),
        ev(physics, 'М', 2, 7, module: true),
      ], labs: [
        ev(physics, 'ЛР', 1, -5, stage: '3'),
        ev(physics, 'ЛР', 2, -3, stage: '3'),
        ev(physics, 'ЛР', 3, -1, stage: '2'),
        ev(physics, 'ЛР', 4, 1, stage: '1'),
      ]),
      d(prog, [
        ev(prog, 'ДЗ', 1, -3, stage: '3'),
        ev(prog, 'М', 1, -3, stage: '13', value: '31', module: true),
        ev(prog, 'КР', 1, 0, stage: '1'),
        ev(prog, 'М', 2, 6, module: true),
      ], labs: [
        ev(prog, 'ЛР', 1, -6, stage: '3'),
        ev(prog, 'ЛР', 2, -4, stage: '3'),
        ev(prog, 'ЛР', 3, -2, stage: '0'),
        ev(prog, 'ЛР', 4, 2),
      ]),
      d(graphics, [
        ev(graphics, 'ДЗ', 1, -5, stage: '3'),
        ev(graphics, 'ДЗ', 2, -1, stage: '1'),
        ev(graphics, 'М', 1, -1, stage: '13', value: '15', module: true),
        ev(graphics, 'ДЗ', 3, 3),
      ]),
      d(materials, [
        ev(materials, 'РК', 1, -1, stage: '3', value: '12'),
        ev(materials, 'ДЗ', 1, 0, stage: '1'),
        ev(materials, 'М', 1, 4, module: true),
      ]),
      d(english, [
        ev(english, 'РК', 1, -2, stage: '3'),
        ev(english, 'ДЗ', 1, 1, stage: '1'),
      ]),
    ];
  }

  // ---------------------------------------------------------------------------
  // Homework notes

  /// Quick notes are due at the real next pair of the demo schedule, long ones in a few days.
  List<HomeworkNote> get homework {
    final lessons = schedule;
    final numerator = week.isNumerator;
    HomeworkNote quick(String id, String discipline, String text, {bool done = false}) {
      final next = nextPairOf(discipline, lessons, currentWeekIsNumerator: numerator, now: now);
      return HomeworkNote(
        id: id,
        disciplineTitle: discipline,
        text: text,
        kind: HomeworkKind.quick,
        due: next?.start ?? now.add(const Duration(days: 2)),
        done: done,
        createdAt: now,
      );
    }

    HomeworkNote long(String id, String discipline, String text, int days) {
      final day = now.add(Duration(days: days));
      return HomeworkNote(
        id: id,
        disciplineTitle: discipline,
        text: text,
        kind: HomeworkKind.long,
        due: DateTime(day.year, day.month, day.day, 23, 59),
        createdAt: now,
      );
    }

    return [
      quick('demo-hw-1', 'Математический анализ', '№ 2105–2112, повторить признаки сходимости рядов'),
      quick('demo-hw-2', 'Физика', 'Решить задачи 3.14 и 3.21 из задачника Чертова'),
      quick('demo-hw-3', 'Иностранный язык', 'Выучить слова к Unit 5, текст на с. 48', done: true),
      long('demo-hw-4', 'Инженерная графика', 'Чертёж детали «Корпус» на формате А3, три вида и разрез', 9),
      long('demo-hw-5', 'Программирование на C++', 'Курсовая: класс «Матрица» с перегрузкой операторов и тестами', 20),
    ];
  }

  // ---------------------------------------------------------------------------
  // Physical culture and session results

  static const _weekdays = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота'];

  PhysicalCultureData get physicalCulture => PhysicalCultureData(
        studyPoints: 34,
        studyAttends: 14,
        medGroup: 'Основная',
        medDate: 'Справка до 31.08',
        medSwim: true,
        canBookStudy: true,
        canBookStudyDisplay: 'Запись открыта',
        groups: [
          FvRecord(
            id: 'demo-fv-1',
            weekDay: _weekdays[1],
            time: '13:50',
            teacherName: 'Смирнов В.А.',
            section: 'ОФП',
            place: 'Манеж СК МГТУ, 4 этаж',
          ),
          FvRecord(
            id: 'demo-fv-2',
            weekDay: _weekdays[5],
            time: '10:15',
            teacherName: 'Кузьмина Т.Н.',
            section: 'Плавание',
            place: 'Бассейн СК МГТУ',
          ),
        ],
        studyResults: [
          FvTermHistory(term: '1 семестр', points: 62, attend: 26),
          FvTermHistory(term: '2 семестр', points: 60, attend: 25),
        ],
      );

  List<SemesterSession> get sessions => const [
        SemesterSession(
          semesterTitle: 'Семестр 2',
          semesterNumber: 2,
          disciplines: [
            SessionDiscipline(title: 'Математический анализ', department: 'ФН1', controlType: 'Экз', hours: 216, grade: 'Хорошо'),
            SessionDiscipline(title: 'Аналитическая геометрия', department: 'ФН1', controlType: 'Экз', hours: 144, grade: 'Отлично'),
            SessionDiscipline(title: 'Основы программирования', department: 'РК6', controlType: 'Экз', hours: 180, grade: 'Отлично'),
            SessionDiscipline(title: 'Инженерная графика', department: 'РК1', controlType: 'Зач', hours: 108, grade: 'Зачтено'),
            SessionDiscipline(title: 'Иностранный язык', department: 'Л4', controlType: 'Зач', hours: 72, grade: 'Зачтено'),
            SessionDiscipline(title: 'Физическая культура и спорт', department: 'ФВ', controlType: 'Зач', hours: 72, grade: 'Зачтено'),
          ],
        ),
        SemesterSession(
          semesterTitle: 'Семестр 1',
          semesterNumber: 1,
          disciplines: [
            SessionDiscipline(title: 'Математический анализ', department: 'ФН1', controlType: 'Экз', hours: 216, grade: 'Удовлетворительно'),
            SessionDiscipline(title: 'Линейная алгебра', department: 'ФН1', controlType: 'Экз', hours: 144, grade: 'Хорошо'),
            SessionDiscipline(title: 'Информатика', department: 'ИУ5', controlType: 'Диф', hours: 108, grade: 'Отлично'),
            SessionDiscipline(title: 'История России', department: 'СГН1', controlType: 'Зач', hours: 72, grade: 'Зачтено'),
            SessionDiscipline(title: 'Физическая культура и спорт', department: 'ФВ', controlType: 'Зач', hours: 72, grade: 'Зачтено'),
          ],
        ),
      ];
}
