import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../models/current_week.dart';
import '../models/schedule_lesson.dart';
import '../models/discipline_progress.dart';
import '../models/physical_culture.dart';
import '../models/session_result.dart';
import 'bmstu_groups_catalog.dart';

class BmstuAuthException implements Exception {
  final String message;
  BmstuAuthException([this.message = 'Сессия устарела или требуется повторная авторизация']);
  @override
  String toString() => message;
}

class TeacherSearchItem {
  final String title;
  final String uuid;

  const TeacherSearchItem({
    required this.title,
    required this.uuid,
  });

  factory TeacherSearchItem.fromJson(Map<String, dynamic> json) => TeacherSearchItem(
        title: json['title']?.toString() ?? '',
        uuid: json['uuid']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'uuid': uuid,
      };
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
  Dio get dio => _dio;
  bool _isAuthenticated = false;
  String? _lastStageUuid;
  String? get lastStageUuid => _lastStageUuid;
  Future<bool> Function()? onSilentRelogin;
  bool _isRelogging = false;

  BmstuApiService() {
    _dio.interceptors.add(CookieManager(cookieJar));
    _dio.interceptors.add(
      QueuedInterceptorsWrapper(
        onError: (DioException err, handler) async {
          final statusCode = err.response?.statusCode;
          final responseData = err.response?.data?.toString() ?? '';
          final isAuthError = statusCode == 401 ||
              statusCode == 403 ||
              responseData.contains('login-actions') ||
              responseData.contains('auth.bmstu.ru');

          final path = err.requestOptions.path;
          final isLoginPath = path.contains('/cookie/login') ||
              path.contains('sso.bmstu.ru') ||
              path.contains('/callback/kc');

          if (isAuthError && !isLoginPath && onSilentRelogin != null && !_isRelogging) {
            _isRelogging = true;
            try {
              final ok = await onSilentRelogin!();
              _isRelogging = false;
              if (ok) {
                final req = err.requestOptions;
                final response = await _dio.request(
                  req.path,
                  data: req.data,
                  queryParameters: req.queryParameters,
                  options: Options(
                    method: req.method,
                    headers: req.headers,
                    contentType: req.contentType,
                    responseType: req.responseType,
                  ),
                );
                return handler.resolve(response);
              }
            } catch (_) {
              _isRelogging = false;
            }
          }
          return handler.next(err);
        },
      ),
    );
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
      final rawStages = s?['stages'] as List? ?? [];
      final stage = rawStages.isNotEmpty ? rawStages[0] as Map<String, dynamic> : null;
      final group = stage?['group'] as Map<String, dynamic>? ?? {};

      // Parse all stages
      final parsedStages = rawStages
          .whereType<Map<String, dynamic>>()
          .map((st) => StudentStage.fromJson(st))
          .toList();

      // Parse agreements
      final rawAgreements = stage?['agreements'] as List? ?? [];
      final parsedAgreements = rawAgreements
          .whereType<Map<String, dynamic>>()
          .map((a) => StudentAgreement.fromJson(a))
          .toList();

      String? qrUrl;
      try {
        final qrResp = await _dio.get('$apiBase/student/qr');
        final qrData = qrResp.data is Map ? qrResp.data : null;
        final q = qrData?['data'] ?? qrData;
        qrUrl = q?['qr'] as String?;
      } catch (_) {}

      final semester = (group['semester'] as num?)?.toInt() ?? 1;
      final dormitory = p['dormitory']?.toString() == 'dormitory.true' ||
          s?['dormitory']?.toString() == 'dormitory.true';

      String? photoUrl;

      // 1. Primary official endpoint: GET $apiBase/student/photo
      try {
        final photoResp = await _dio.get('$apiBase/student/photo');
        if (photoResp.statusCode == 200 && photoResp.data is Map) {
          final rawPhoto = (photoResp.data as Map)['photo']?.toString();
          if (rawPhoto != null && rawPhoto.isNotEmpty) {
            if (rawPhoto.startsWith('data:image')) {
              photoUrl = rawPhoto;
            } else if (rawPhoto.startsWith('/9j/') || rawPhoto.startsWith('iVBOR')) {
              photoUrl = 'data:image/jpeg;base64,$rawPhoto';
            } else if (rawPhoto.startsWith('http://') || rawPhoto.startsWith('https://')) {
              photoUrl = rawPhoto;
            } else {
              photoUrl = 'data:image/jpeg;base64,$rawPhoto';
            }
          }
        }
      } catch (_) {}

      // 2. Scrape student photo from https://lks.bmstu.ru/profile (_img_1rxc3_40 _visible_1rxc3_45)
      if (photoUrl == null || photoUrl.isEmpty) {
        try {
          final profilePageResp = await _dio.get('https://lks.bmstu.ru/profile');
          if (profilePageResp.statusCode == 200 && profilePageResp.data != null) {
            final scrapedPhoto = parseProfilePhotoHtml(profilePageResp.data.toString());
            if (scrapedPhoto != null && scrapedPhoto.isNotEmpty) {
              photoUrl = scrapedPhoto;
            }
          }
        } catch (_) {}
      }

      // 3. Fallback to person/student API fields
      if (photoUrl == null || photoUrl.isEmpty) {
        photoUrl = p['photoUrl']?.toString() ??
            p['photo']?.toString() ??
            p['avatarUrl']?.toString() ??
            p['avatar']?.toString() ??
            p['photo_url']?.toString() ??
            s?['photoUrl']?.toString() ??
            s?['photo']?.toString() ??
            s?['avatar']?.toString();

        if (photoUrl != null && photoUrl.isNotEmpty) {
          if (!photoUrl.startsWith('data:') &&
              !photoUrl.startsWith('http://') &&
              !photoUrl.startsWith('https://')) {
            if (!photoUrl.startsWith('/')) {
              photoUrl = '/$photoUrl';
            }
            photoUrl = 'https://lks.bmstu.ru$photoUrl';
          }
        } else if (p['uuid'] != null && p['uuid'].toString().isNotEmpty) {
          photoUrl = 'https://lks.bmstu.ru/media/avatar/${p['uuid']}';
        }
      }

      _lastStageUuid = stage?['uuid']?.toString();

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
        photoUrl: photoUrl,
        cardNumber: stage?['cardNumber']?.toString(),
        semester: semester,
        specialityTitle: group['specialityTitle']?.toString(),
        specializationTitle: group['specializationTitle']?.toString(),
        studyType: stage?['studyType']?.toString(),
        state: stage?['state']?.toString() ?? 'Обучается',
        hasDormitory: dormitory,
        birthDate: p['birthDate']?.toString(),
        agreements: parsedAgreements,
        stages: parsedStages,
      );
    } catch (e) {
      return null;
    }
  }

  // Current Week
  Future<CurrentWeek?> getCurrentWeek({bool fallbackToDefault = true}) async {
    try {
      final resp = await _dio.get('$apiBase/schedules/current');
      if (resp.statusCode == 200 && resp.data is Map) {
        final data = resp.data['data'] ?? resp.data;
        if (data is Map<String, dynamic>) {
          return CurrentWeek.fromJson(data);
        }
      }
    } catch (_) {}
    return fallbackToDefault ? CurrentWeek.defaultWeek() : null;
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
    final pubResp = await _dio.get('$apiBase/schedules/groups/$groupUuid/public');
    if (pubResp.statusCode == 200 && pubResp.data is Map) {
      final data = pubResp.data['data'] ?? pubResp.data;
      final sched = data?['schedule'] as List?;
      if (sched != null) {
        return normalizeSchedule(sched);
      }
    }

    return [];
  }

  // Get Schedule for Teacher
  Future<List<ScheduleLesson>> getTeacherSchedule(String teacherUuid) async {
    if (teacherUuid.isEmpty) return [];

    try {
      final resp = await _dio.get('$apiBase/schedules/teacher/$teacherUuid');
      if (resp.statusCode == 200) {
        if (resp.data is Map) {
          final data = resp.data['data'] ?? resp.data;
          final sched = (data is Map ? data['schedule'] : null) as List? ??
              (data is List ? data : null);
          if (sched != null) {
            return normalizeSchedule(sched);
          }
        } else if (resp.data is List) {
          return normalizeSchedule(resp.data as List);
        }
      }
    } on DioException catch (dioErr) {
      if (dioErr.response?.statusCode == 401 || dioErr.response?.statusCode == 403) {
        throw BmstuAuthException('Сессия устарела или требуется авторизация в ЛКС');
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
    } catch (_) {}
    // Fallback to local 3401 catalog
    return BmstuGroupsCatalog.search(query);
  }

  // Online search for teachers
  Future<List<TeacherSearchItem>> searchTeachersOnline(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];
    try {
      final resp = await _dio.get(
        '$apiBase/schedules/search',
        queryParameters: {'s': cleanQuery},
      );
      if (resp.statusCode == 200 && resp.data is List) {
        final list = resp.data as List;
        final results = <TeacherSearchItem>[];
        for (final item in list) {
          if (item is Map && item['type'] == 'teacher') {
            final title = item['title']?.toString() ?? '';
            final uuid = (item['uuid'] ?? item['id'])?.toString() ?? '';
            if (title.isNotEmpty && uuid.isNotEmpty) {
              results.add(TeacherSearchItem(
                title: title,
                uuid: uuid,
              ));
            }
          }
        }
        return results;
      }
    } on DioException catch (dioErr) {
      if (dioErr.response?.statusCode == 401 || dioErr.response?.statusCode == 403) {
        throw BmstuAuthException('Для поиска преподавателей требуется авторизация в ЛКС');
      }
    } catch (_) {}
    return [];
  }

  // Scrape student photo from HTML of https://lks.bmstu.ru/profile
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
        final dt = DateTime.parse(rawDate).toLocal();
        final day = dt.day.toString().padLeft(2, '0');
        final month = dt.month.toString().padLeft(2, '0');
        final year = dt.year;
        final hour = dt.hour.toString().padLeft(2, '0');
        final min = dt.minute.toString().padLeft(2, '0');
        lastUpdated = 'Данные актуальны на $day.$month.$year $hour:$min';
      } catch (_) {
        lastUpdated = 'Данные актуальны на $rawDate';
      }
    }

    final rawData = json['data'] as List? ?? [];
    for (final item in rawData) {
      if (item is! Map) continue;
      final term = (item['term'] as num?)?.toInt() ?? 1;
      final rawMarks = item['marks'] as List? ?? [];
      final disciplines = <SessionDiscipline>[];

      for (final m in rawMarks) {
        if (m is! Map) continue;
        final discName = m['disciplineName']?.toString() ?? '';
        final dept = m['disciplineDepartment']?.toString() ?? '';
        final control = m['testTitleShort']?.toString() ?? '';
        final hours = (m['audlek'] as num?)?.toInt() ?? 0;
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

  // Get Session Results (from official API, HTML scraping, or cache)
  Future<List<SemesterSession>> getSessionResults({
    String? stageUuid,
    bool forceRefresh = false,
  }) async {
    const cacheKey = 'bmstu_session_results_cache';
    final prefs = await SharedPreferences.getInstance();
    final targetStage = (stageUuid != null && stageUuid.isNotEmpty) ? stageUuid : _lastStageUuid;

    // 1. If not forcing refresh, try cache first if available
    if (!forceRefresh) {
      final cachedJson = prefs.getString(cacheKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(cachedJson) as List;
          final cachedList = decoded
              .whereType<Map<String, dynamic>>()
              .map((s) => SemesterSession.fromJson(s))
              .toList();
          if (cachedList.isNotEmpty) {
            // Trigger background refresh if authenticated
            if (_isAuthenticated) {
              _fetchAndCacheSessionResults(prefs, cacheKey, stageUuid: targetStage)
                  .catchError((_) => <SemesterSession>[]);
            }
            return cachedList;
          }
        } catch (_) {}
      }
    }

    // 2. Fetch live data
    try {
      final liveSessions = await _fetchAndCacheSessionResults(prefs, cacheKey, stageUuid: targetStage);
      if (liveSessions.isNotEmpty) return liveSessions;
    } catch (e) {
      // 3. On error, fallback to cache
      final cachedJson = prefs.getString(cacheKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(cachedJson) as List;
          return decoded
              .whereType<Map<String, dynamic>>()
              .map((s) => SemesterSession.fromJson(s))
              .toList();
        } catch (_) {}
      }
      rethrow;
    }

    return [];
  }

  Future<List<SemesterSession>> _fetchAndCacheSessionResults(
    SharedPreferences prefs,
    String cacheKey, {
    String? stageUuid,
  }) async {
    var targetStage = (stageUuid != null && stageUuid.isNotEmpty) ? stageUuid : _lastStageUuid;

    // Resolve stageUuid from $apiBase/student if not known
    if ((targetStage == null || targetStage.isEmpty) && _isAuthenticated) {
      try {
        final studentResp = await _dio.get('$apiBase/student');
        if (studentResp.data is Map) {
          final s = studentResp.data['data'] ?? studentResp.data;
          final rawStages = s?['stages'] as List? ?? [];
          if (rawStages.isNotEmpty && rawStages[0] is Map) {
            targetStage = rawStages[0]['uuid']?.toString();
            _lastStageUuid = targetStage;
          }
        }
      } catch (_) {}
    }

    // 1. Primary official JSON API endpoint
    if (targetStage != null && targetStage.isNotEmpty) {
      try {
        final resp = await _dio.get('$apiBase/student/$targetStage/sessions');
        if (resp.statusCode == 200 && resp.data is Map) {
          final sessions = parseSessionJson(Map<String, dynamic>.from(resp.data as Map));
          if (sessions.isNotEmpty) {
            final jsonList = sessions.map((s) => s.toJson()).toList();
            await prefs.setString(cacheKey, jsonEncode(jsonList));
            return sessions;
          }
        }
      } catch (_) {}
    }

    // 2. Fallback to HTML scraping
    try {
      final resp = await _dio.get('https://lks.bmstu.ru/session');
      if (resp.statusCode == 200 && resp.data != null) {
        final html = resp.data.toString();
        final sessions = parseSessionHtml(html);
        if (sessions.isNotEmpty) {
          final jsonList = sessions.map((s) => s.toJson()).toList();
          await prefs.setString(cacheKey, jsonEncode(jsonList));
          return sessions;
        }
      }
    } catch (_) {}

    return [];
  }
}
