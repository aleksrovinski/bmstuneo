import '../models/discipline_progress.dart';
import '../models/schedule_lesson.dart';
import '../models/session_result.dart';
import '../constants/moscow_time.dart';

/// Turns raw LKS responses (JSON and scraped HTML) into the app's models.
/// No network and no state: everything here can be tested on a string.
abstract final class LksParsers {
  /// Lessons of a group or teacher schedule as LKS returns them.
  static List<ScheduleLesson> schedule(List<dynamic> rawList) {
    return rawList.map((item) {
      final map = item as Map<String, dynamic>;

      // Audiences
      final rawAuds = map['audiences'] as List? ?? [];
      final audiences = rawAuds.map((a) {
        final aMap = a as Map<String, dynamic>;
        final name = aMap['name']?.toString() ?? '—';
        String? bld = aMap['building']?.toString();

        if (bld == null || bld == 'None' || bld.isEmpty) {
          if (name.endsWith('л')) {
            bld = 'УЛК';
          } else if (name == '323' || name == '384' || name.startsWith('Ауд.')) {
            bld = 'ГУК';
          } else if (name.contains('ФН')) {
            bld = 'Кафедра ФН';
          } else if (name.contains('МТ')) {
            bld = 'Кафедра МТ';
          } else if (name.contains('Л')) {
            bld = 'Кафедра Л';
          } else if (name.contains('ФВ') || name.startsWith('С/к')) {
            bld = 'Спорткомплекс';
          }
        } else {
          bld = bld.replaceAll(RegExp(r'^[A-Z0-9]+\s*'), ''); // strip 'E1 ', 'A1 '
        }

        return ScheduleAudience(name: name, building: bld, uuid: aMap['uuid']?.toString());
      }).toList();

      // Teachers
      final rawTeachers = map['teachers'] as List? ?? [];
      final teachers = rawTeachers.map((t) {
        final tMap = t as Map<String, dynamic>;
        return ScheduleTeacher(
          firstName: tMap['firstName']?.toString() ?? '',
          lastName: tMap['lastName']?.toString() ?? '',
          middleName: tMap['middleName']?.toString() ?? '',
          uuid: tMap['uuid']?.toString(),
        );
      }).toList();

      final disc = map['discipline'] as Map<String, dynamic>? ?? {};
      final stream = map['stream'] as Map<String, dynamic>?;
      var streamName = stream?['name']?.toString();
      if (streamName == null || streamName.isEmpty) {
        final rawGroups = map['groups'] as List?;
        if (rawGroups != null && rawGroups.isNotEmpty) {
          final gNames = rawGroups
              .map((g) => (g is Map ? (g['name'] ?? g['title']) : g)?.toString() ?? '')
              .where((g) => g.isNotEmpty)
              .join(', ');
          if (gNames.isNotEmpty) {
            streamName = gNames;
          }
        }
      }
      final isStream = streamName != null && (streamName.contains(';') || streamName.contains(','));

      return ScheduleLesson(
        day: (map['day'] as num?)?.toInt() ?? 1,
        time: (map['time'] as num?)?.toInt() ?? 1,
        startTime: map['startTime']?.toString() ?? '08:30',
        endTime: map['endTime']?.toString() ?? '10:00',
        week: map['week']?.toString() ?? 'all',
        disciplineTitle: disc['fullName']?.toString() ?? 'Дисциплина',
        actType: disc['actType']?.toString() ?? 'seminar',
        audiences: audiences,
        teachers: teachers,
        streamName: streamName,
        isStream: isStream,
      );
    }).toList();
  }

  /// Disciplines of the progress (БРС) response with their controls, labs and seminars.
  static List<DisciplineProgress> progress(List<dynamic> disciplines) {
    return disciplines.map((d) {
      final dMap = d as Map<String, dynamic>;
      final discTitle = dMap['title']?.toString() ?? 'Дисциплина';

      final rawControls = dMap['controls'] as List? ?? [];
      final rawLabs = dMap['laboratory'] as List? ?? [];
      final rawSeminars = dMap['seminars'] as List? ?? [];

      return DisciplineProgress(
        title: discTitle,
        disciplineUuid: dMap['disciplineUuid']?.toString(),
        points: dMap['points'] is Map ? Map<String, dynamic>.from(dMap['points'] as Map) : {},
        controls: _eventList(rawControls, discTitle),
        laboratory: _eventList(rawLabs, discTitle),
        seminars: _eventList(rawSeminars, discTitle),
      );
    }).toList();
  }

  static List<ControlEvent> _eventList(List<dynamic> rawList, String discTitle) {
    final counts = <String, int>{};
    return rawList.map((c) {
      final cMap = c as Map<String, dynamic>;
      final type = cMap['type']?.toString() ?? 'КМ';
      counts[type] = (counts[type] ?? 0) + 1;
      final countIdx = counts[type]!;

      String defaultTitle;
      if (type == 'ДЗ') {
        defaultTitle = 'ДЗ-$countIdx';
      } else if (type == 'РК') {
        defaultTitle = 'РК-$countIdx';
      } else if (type == 'КР') {
        defaultTitle = 'КР-$countIdx';
      } else if (type == 'ЛР') {
        defaultTitle = 'ЛР-$countIdx';
      } else if (type == 'СЗ') {
        defaultTitle = 'Семинар $countIdx';
      } else if (type == 'М') {
        defaultTitle = 'Модуль $countIdx';
      } else {
        defaultTitle = '$type-$countIdx';
      }

      int week = 1;
      final rawWeek = cMap['week'];
      if (rawWeek is num) {
        week = rawWeek.toInt();
      } else if (rawWeek is String) {
        week = int.tryParse(rawWeek) ?? 1;
      }

      return ControlEvent(
        type: type,
        title: cMap['title']?.toString() ?? defaultTitle,
        week: week,
        value: cMap['value'],
        stage: cMap['stage']?.toString(),
        passStatus: cMap['passStatus']?.toString(),
        setDate: cMap['setDate']?.toString(),
        disciplineTitle: discTitle,
        controlIndex: countIdx,
        controlId: cMap['controlId']?.toString(),
        points: cMap['points'] is Map ? Map<String, dynamic>.from(cMap['points'] as Map) : null,
      );
    }).toList();
  }

  /// Finds where the Keycloak login form posts credentials.
  ///
  /// Only the login form itself is accepted (id `kc-form-login`, or an action
  /// pointing at `login-actions/authenticate`), and only on sso.bmstu.ru, so the
  /// password is never sent to some other form or host on the page.
  static String? extractLoginFormAction(String html, Uri pageUri) {
    final formTag = RegExp(r'<form\b[^>]*>', caseSensitive: false);
    String? attr(String tag, String name) => RegExp(
          '\\b$name\\s*=\\s*["\']([^"\']*)["\']',
          caseSensitive: false,
        ).firstMatch(tag)?.group(1);

    String? byId;
    String? byAction;
    for (final m in formTag.allMatches(html)) {
      final tag = m.group(0)!;
      final action = attr(tag, 'action');
      if (action == null || action.isEmpty) continue;
      if (attr(tag, 'id') == 'kc-form-login') {
        byId ??= action;
      } else if (action.contains('login-actions/authenticate')) {
        byAction ??= action;
      }
    }

    final raw = byId ?? byAction;
    if (raw == null) return null;
    final resolved = pageUri.resolve(raw.replaceAll('&amp;', '&'));
    if (resolved.scheme != 'https' || resolved.host != 'sso.bmstu.ru') return null;
    return resolved.toString();
  }

  static String? parseProfilePhotoHtml(String html) {
    final imgRegex = RegExp(r'<img[^>]+>', caseSensitive: false);
    for (final match in imgRegex.allMatches(html)) {
      final tag = match.group(0) ?? '';
      if (tag.contains('_img_1rxc3_40') || tag.contains('_visible_1rxc3_45')) {
        final srcMatch = RegExp(r'src="([^"]+)"', caseSensitive: false).firstMatch(tag);
        if (srcMatch != null) {
          final src = srcMatch.group(1);
          if (src != null && src.trim().isNotEmpty) {
            final trimmed = src.trim();
            if (trimmed.startsWith('data:image') ||
                trimmed.startsWith('http://') ||
                trimmed.startsWith('https://')) {
              return trimmed;
            }
            if (trimmed.startsWith('/')) {
              return 'https://lks.bmstu.ru$trimmed';
            }
            return 'https://lks.bmstu.ru/$trimmed';
          }
        }
      }
    }
    return null;
  }

  // Parse Session Results from HTML of https://lks.bmstu.ru/session
  static List<SemesterSession> parseSessionHtml(String html) {
    final List<SemesterSession> sessions = [];

    // Optional: Extract "Данные актуальны на ..."
    String? lastUpdated;
    final updatedMatch = RegExp(r'<i>\s*(Данные актуальны на [^<]+)\s*</i>', caseSensitive: false).firstMatch(html);
    if (updatedMatch != null) {
      lastUpdated = updatedMatch.group(1)?.trim();
    }

    // Match each article block
    final articleRegex = RegExp(
      r'<article[^>]*class="[^"]*table-container[^"]*"[^>]*>([\s\S]*?)(?=<\/article>|$)',
      caseSensitive: false,
    );

    final articleMatches = articleRegex.allMatches(html);
    for (final articleMatch in articleMatches) {
      final articleContent = articleMatch.group(1) ?? '';

      // Title: e.g. "Семестр 2"
      final titleMatch = RegExp(r'<h1[^>]*>([\s\S]*?Семестр\s*(\d+)[\s\S]*?)<\/h1>', caseSensitive: false)
          .firstMatch(articleContent);
      final rawTitle = titleMatch != null ? titleMatch.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim() : 'Семестр';
      final semNum = titleMatch != null ? int.tryParse(titleMatch.group(2) ?? '1') ?? 1 : 1;

      // Extract rows from tbody
      final tbodyMatch = RegExp(r'<tbody[^>]*>([\s\S]*?)<\/tbody>', caseSensitive: false).firstMatch(articleContent);
      final tbodyContent = tbodyMatch != null ? tbodyMatch.group(1)! : articleContent;

      final rowRegex = RegExp(r'<tr[^>]*role="row"[^>]*>([\s\S]*?)<\/tr>', caseSensitive: false);
      final rowMatches = rowRegex.allMatches(tbodyContent);

      final List<SessionDiscipline> disciplines = [];

      for (final rowMatch in rowMatches) {
        final rowContent = rowMatch.group(1) ?? '';
        final tdRegex = RegExp(r'<td[^>]*>([\s\S]*?)<\/td>', caseSensitive: false);
        final tdMatches = tdRegex.allMatches(rowContent).toList();
        if (tdMatches.length < 3) continue;

        final col1 = tdMatches[0].group(1) ?? '';
        final col2 = tdMatches[1].group(1) ?? '';
        final col3 = tdMatches[2].group(1) ?? '';

        String title = '';
        String department = '';
        String controlType = '';

        final deptMatch = RegExp(r'\(([^,]+),\s*([^)]+)\)').firstMatch(col1);
        if (deptMatch != null) {
          department = deptMatch.group(1)!.trim();
          controlType = deptMatch.group(2)!.trim();
          final rawWithoutSpan = col1.replaceAll(RegExp(r'<span[^>]*>[\s\S]*?<\/span>'), '');
          title = rawWithoutSpan.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&nbsp;', ' ').trim();
        } else {
          title = col1.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&nbsp;', ' ').trim();
        }

        final hoursStr = col2.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        final hours = int.tryParse(hoursStr) ?? 0;

        String grade = '';
        final titleAttrMatch = RegExp(r'title="([^"]+)"').firstMatch(col3);
        if (titleAttrMatch != null && titleAttrMatch.group(1)!.trim().isNotEmpty) {
          grade = titleAttrMatch.group(1)!.trim();
        } else {
          grade = col3.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&nbsp;', ' ').trim();
        }

        if (title.isNotEmpty) {
          disciplines.add(SessionDiscipline(
            title: title,
            department: department,
            controlType: controlType,
            hours: hours,
            grade: grade,
          ));
        }
      }

      if (disciplines.isNotEmpty) {
        sessions.add(SemesterSession(
          semesterTitle: rawTitle,
          semesterNumber: semNum,
          disciplines: disciplines,
          lastUpdated: lastUpdated,
        ));
      }
    }

    sessions.sort((a, b) => b.semesterNumber.compareTo(a.semesterNumber));
    return sessions;
  }

  // Parse Session Results from official JSON API ($apiBase/student/$stageUuid/sessions)
  static List<SemesterSession> parseSessionJson(Map<String, dynamic> json) {
    final List<SemesterSession> sessions = [];
    String? lastUpdated;
    final rawDate = json['date']?.toString();
    if (rawDate != null && rawDate.isNotEmpty) {
      try {
        // Moscow time, as the LKS website shows it; a date without an offset already is
        final parsed = DateTime.parse(rawDate);
        final dt = parsed.isUtc ? MoscowTime.of(parsed) : parsed;
        const months = [
          'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
          'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
        ];
        final day = dt.day;
        final month = months[dt.month - 1];
        final hour = dt.hour.toString().padLeft(2, '0');
        final min = dt.minute.toString().padLeft(2, '0');
        lastUpdated = 'Данные актуальны на $day $month $hour:$min';
      } catch (_) {
        lastUpdated = 'Данные актуальны на $rawDate';
      }
    }

    final rawData = json['data'] as List? ?? [];
    for (final item in rawData) {
      if (item is! Map) continue;
      int term = 1;
      final rawTerm = item['term'];
      if (rawTerm is num) {
        term = rawTerm.toInt();
      } else if (rawTerm is String) {
        term = int.tryParse(rawTerm) ?? 1;
      }

      final rawMarks = item['marks'] as List? ?? [];
      final disciplines = <SessionDiscipline>[];

      for (final m in rawMarks) {
        if (m is! Map) continue;
        final discName = m['disciplineName']?.toString() ?? '';
        final dept = m['disciplineDepartment']?.toString() ?? '';
        final control = m['testTitleShort']?.toString() ?? '';
        int hours = 0;
        final rawAudlek = m['audlek'];
        if (rawAudlek is num) {
          hours = rawAudlek.toInt();
        } else if (rawAudlek is String) {
          hours = int.tryParse(rawAudlek) ?? 0;
        }
        final grade = m['title']?.toString() ?? '';

        if (discName.isNotEmpty) {
          disciplines.add(SessionDiscipline(
            title: discName,
            department: dept,
            controlType: control,
            hours: hours,
            grade: grade,
          ));
        }
      }

      sessions.add(SemesterSession(
        semesterTitle: 'Семестр $term',
        semesterNumber: term,
        disciplines: disciplines,
        lastUpdated: lastUpdated,
      ));
    }

    sessions.sort((a, b) => b.semesterNumber.compareTo(a.semesterNumber));
    return sessions;
  }
}
