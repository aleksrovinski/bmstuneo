import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import '../models/user_profile.dart';
import '../models/current_week.dart';
import '../models/schedule_lesson.dart';
import '../models/discipline_progress.dart';
import '../models/physical_culture.dart';
import 'bmstu_groups_catalog.dart';

class BmstuAuthException implements Exception {
  final String message;
  BmstuAuthException([this.message = 'Сессия устарела или требуется повторная авторизация']);
  @override
  String toString() => message;
}

class BmstuApiService {
  static const String apiBase = 'https://lks.bmstu.ru/lks-back/api/v1';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) BMSTU-LKS-Flutter/1.0',
        'Accept': 'application/json',
      },
    ),
  );

  final CookieJar cookieJar = CookieJar();
  bool _isAuthenticated = false;

  BmstuApiService() {
    _dio.interceptors.add(CookieManager(cookieJar));
  }

  bool get isAuthenticated => _isAuthenticated;

  // Real-time Keycloak SSO Login
  Future<UserProfile?> login(String username, String password) async {
    try {
      _dio.options.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) BMSTU-LKS-Flutter/1.0';

      // 1. Initial request to LKS login endpoint (gets redirected to sso.bmstu.ru)
      final initResp = await _dio.get<String>(
        'https://lks.bmstu.ru/portal4/cookie/login',
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      String? ssoUrl = initResp.headers.value('location');
      if (ssoUrl == null || !ssoUrl.contains('sso.bmstu.ru')) {
        final resp2 = await _dio.get<String>('https://lks.bmstu.ru/portal4/cookie/login');
        ssoUrl = resp2.realUri.toString();
      }

      if (ssoUrl.isEmpty || !ssoUrl.contains('sso.bmstu.ru')) {
        throw Exception('Не удалось подключиться к серверу авторизации МГТУ');
      }

      // 2. Fetch Keycloak HTML Form
      final ssoPageResp = await _dio.get<String>(ssoUrl);
      final ssoHtml = ssoPageResp.data ?? '';

      final actionRegex = RegExp(r'''action=["']([^"']+)["']''', caseSensitive: false);
      final match = actionRegex.firstMatch(ssoHtml);
      if (match == null) {
        throw Exception('Форма авторизации Keycloak не найдена');
      }

      final actionUrl = match.group(1)!.replaceAll('&amp;', '&');

      // 3. Post Credentials to Keycloak
      final authResp = await _dio.post(
        actionUrl,
        data: {
          'username': username,
          'password': password,
          'credentialId': '',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
          headers: {'Referer': ssoUrl},
        ),
      );

      final callbackUrl = authResp.headers.value('location');
      if (callbackUrl != null && callbackUrl.contains('/portal4/upstream/callback/kc')) {
        await _dio.get(
          callbackUrl,
          options: Options(
            followRedirects: false,
            validateStatus: (status) => status != null && status < 500,
          ),
        );
      } else {
        final bodyStr = authResp.data?.toString() ?? '';
        if (bodyStr.contains('kc-feedback-text') ||
            bodyStr.contains('alert-error') ||
            bodyStr.contains('Invalid username or password') ||
            bodyStr.contains('Неверное имя пользователя или пароль')) {
          throw Exception('Неверный логин или пароль студента');
        }
      }

      // 4. Verify Profile
      final profile = await fetchUserProfile();
      if (profile == null) {
        throw Exception('Неверный логин или пароль, либо ошибка сессии');
      }

      _isAuthenticated = true;
      return profile;
    } catch (e) {
      _isAuthenticated = false;
      rethrow;
    }
  }

  // Fetch Student Profile from /person and /student
  Future<UserProfile?> fetchUserProfile() async {
    try {
      final personResp = await _dio.get('$apiBase/person');
      final personData = personResp.data is Map ? personResp.data : null;
      if (personData == null) return null;

      final p = personData['data'] ?? personData;
      if (p['firstName'] == null) return null;

      final studentResp = await _dio.get('$apiBase/student');
      final studentData = studentResp.data is Map ? studentResp.data : null;
      final s = studentData?['data'] ?? studentData;
      final stages = s?['stages'] as List? ?? [];
      final stage = stages.isNotEmpty ? stages[0] as Map<String, dynamic> : null;
      final group = stage?['group'] as Map<String, dynamic>? ?? {};

      String? qrUrl;
      try {
        final qrResp = await _dio.get('$apiBase/student/qr');
        final qrData = qrResp.data is Map ? qrResp.data : null;
        final q = qrData?['data'] ?? qrData;
        qrUrl = q?['qr'] as String?;
      } catch (_) {}

      return UserProfile(
        lastName: p['lastName']?.toString() ?? '',
        firstName: p['firstName']?.toString() ?? '',
        middleName: p['middleName']?.toString() ?? '',
        groupTitle: group['title']?.toString() ?? 'Студент',
        groupCode: group['code']?.toString(),
        groupUuid: group['uuid']?.toString() ?? '',
        stageUuid: stage?['uuid']?.toString() ?? '',
        personUuid: p['uuid']?.toString(),
        qrUrl: qrUrl,
      );
    } catch (e) {
      return null;
    }
  }

  // Current Week
  Future<CurrentWeek> getCurrentWeek() async {
    try {
      final resp = await _dio.get('$apiBase/schedules/current');
      if (resp.statusCode == 200 && resp.data is Map) {
        final data = resp.data['data'] ?? resp.data;
        if (data is Map<String, dynamic>) {
          return CurrentWeek.fromJson(data);
        }
      }
    } catch (_) {}
    return CurrentWeek.defaultWeek();
  }

  // Schedule normalization
  List<ScheduleLesson> normalizeSchedule(List<dynamic> rawList) {
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
      final streamName = stream?['name']?.toString();
      final isStream = streamName != null && streamName.contains(';');

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

  // Get Schedule for Group
  Future<List<ScheduleLesson>> getGroupSchedule(String groupUuid) async {
    if (groupUuid.isEmpty) return [];

    // 1. Try private endpoint if authenticated
    if (_isAuthenticated) {
      try {
        final privResp = await _dio.get('$apiBase/schedules/groups/$groupUuid/private');
        if (privResp.statusCode == 200 && privResp.data is Map) {
          final data = privResp.data['data'] ?? privResp.data;
          final sched = data?['schedule'] as List?;
          if (sched != null && sched.isNotEmpty) {
            return normalizeSchedule(sched);
          }
        }
      } catch (_) {}
    }

    // 2. Try public endpoint
    try {
      final pubResp = await _dio.get('$apiBase/schedules/groups/$groupUuid/public');
      if (pubResp.statusCode == 200 && pubResp.data is Map) {
        final data = pubResp.data['data'] ?? pubResp.data;
        final sched = data?['schedule'] as List?;
        if (sched != null) {
          return normalizeSchedule(sched);
        }
      }
    } catch (_) {}

    return [];
  }

  // Progress, controls, laboratory, and seminars
  Future<List<DisciplineProgress>> getProgress(String stageUuid) async {
    if (stageUuid.isEmpty) return [];
    try {
      final resp = await _dio.get('$apiBase/student/$stageUuid/progress');
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        throw BmstuAuthException('Сессия ЛКС устарела (${resp.statusCode})');
      }

      if (resp.statusCode == 200 && resp.data is Map) {
        final root = resp.data['data'] ?? resp.data;
        final student = root?['student'] ?? root;
        final disciplines = student?['disciplines'] as List? ?? [];

        return disciplines.map((d) {
          final dMap = d as Map<String, dynamic>;
          final discTitle = dMap['title']?.toString() ?? 'Дисциплина';

          final rawControls = dMap['controls'] as List? ?? [];
          final rawLabs = dMap['laboratory'] as List? ?? [];
          final rawSeminars = dMap['seminars'] as List? ?? [];

          return DisciplineProgress(
            title: discTitle,
            disciplineUuid: dMap['disciplineUuid']?.toString(),
            points: dMap['points'] is Map ? Map<String, dynamic>.from(dMap['points']) : {},
            controls: _parseEventList(rawControls, discTitle),
            laboratory: _parseEventList(rawLabs, discTitle),
            seminars: _parseEventList(rawSeminars, discTitle),
          );
        }).toList();
      }

      // Check if Keycloak SSO returned an HTML login page
      final dataStr = resp.data?.toString() ?? '';
      if (dataStr.contains('login-actions') || dataStr.contains('auth.bmstu.ru')) {
        throw BmstuAuthException('Сессия ЛКС устарела (перенаправление на вход)');
      }
    } on DioException catch (dioErr) {
      if (dioErr.response?.statusCode == 401 || dioErr.response?.statusCode == 403) {
        throw BmstuAuthException('Сессия ЛКС устарела');
      }
      final respStr = dioErr.response?.data?.toString() ?? '';
      if (respStr.contains('login') || respStr.contains('auth.bmstu.ru')) {
        throw BmstuAuthException('Сессия ЛКС устарела (SSO)');
      }
      rethrow;
    }
    return [];
  }

  List<ControlEvent> _parseEventList(List rawList, String discTitle) {
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
        points: cMap['points'] is Map ? Map<String, dynamic>.from(cMap['points']) : null,
      );
    }).toList();
  }

  // Physical culture (ФКиС)
  Future<PhysicalCultureData?> getPhysicalCulture(String stageUuid) async {
    if (stageUuid.isEmpty) return null;
    try {
      final resp = await _dio.get('$apiBase/fv/$stageUuid/me');
      if (resp.statusCode == 200 && resp.data is Map) {
        final data = resp.data['data'] ?? resp.data;
        if (data is Map<String, dynamic>) {
          return PhysicalCultureData.fromJson(data);
        }
      }
    } catch (_) {}
    return null;
  }

  // Online search for groups
  Future<List<GroupItem>> searchGroupsOnline(String query) async {
    if (query.trim().isEmpty) return BmstuGroupsCatalog.popularGroups;
    try {
      if (_isAuthenticated) {
        final resp = await _dio.get(
          '$apiBase/schedules/search',
          queryParameters: {'s': query.trim()},
        );
        if (resp.statusCode == 200 && resp.data is List) {
          final list = resp.data as List;
          final results = <GroupItem>[];
          for (final item in list) {
            if (item is Map && item['type'] == 'group') {
              results.add(GroupItem(
                title: item['title']?.toString() ?? '',
                uuid: item['uuid']?.toString() ?? '',
              ));
            }
          }
          if (results.isNotEmpty) return results;
        }
      }
    } catch (_) {}
    // Fallback to local 3401 catalog
    return BmstuGroupsCatalog.search(query);
  }
}
