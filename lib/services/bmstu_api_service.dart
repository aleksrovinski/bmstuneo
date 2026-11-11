import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import '../models/user_profile.dart';
import '../models/current_week.dart';
import '../models/schedule_lesson.dart';
import '../models/discipline_progress.dart';
import '../models/physical_culture.dart';
import '../models/session_result.dart';
import 'bmstu_groups_catalog.dart';
import 'cache_store.dart';
import 'lks_errors.dart';
import 'lks_parsers.dart';
import '../models/teacher_search_item.dart';

export 'lks_errors.dart';
export '../models/teacher_search_item.dart';

class BmstuApiService {
  static const String apiBase = 'https://lks.bmstu.ru/lks-back/api/v1';

  static BaseOptions _baseOptions() => BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) BMSTU-LKS-Flutter/1.0',
          'Accept': 'application/json',
        },
      );

  static const _kRetriedAfterRelogin = 'bmstu_retried_after_relogin';

  // Regular API traffic; recovers from an expired session via [onSilentRelogin]
  final Dio _dio = Dio(_baseOptions());
  // SSO login and profile fetch. Shares cookies with [_dio] but has no relogin
  // interceptor, so a 401 during login fails the login instead of waiting on itself.
  final Dio _authDio = Dio(_baseOptions());

  /// In-memory by default (tests); the app passes a jar persisted in secure storage.
  final CookieJar cookieJar;
  Dio get dio => _dio;
  bool _isAuthenticated = false;
  String? _lastStageUuid;
  String? get lastStageUuid => _lastStageUuid;
  Future<bool> Function()? onSilentRelogin;
  Future<bool>? _reloginInFlight;

  BmstuApiService({CookieJar? cookieJar}) : cookieJar = cookieJar ?? CookieJar() {
    _authDio.interceptors.add(CookieManager(this.cookieJar));
    _dio.interceptors.add(CookieManager(this.cookieJar));
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException err, handler) async {
          final req = err.requestOptions;
          if (!_isSessionExpired(err) ||
              req.extra[_kRetriedAfterRelogin] == true ||
              onSilentRelogin == null) {
            return handler.next(err);
          }

          if (!await _reloginOnce()) return handler.next(err);

          try {
            // Drop the stale cookie header so CookieManager sends the fresh session
            final retry = req.copyWith(
              headers: Map.of(req.headers)..remove('cookie'),
              extra: {...req.extra, _kRetriedAfterRelogin: true},
            );
            return handler.resolve(await _dio.fetch(retry));
          } on DioException catch (e) {
            return handler.next(e);
          }
        },
      ),
    );
  }

  /// Replaces the HTTP client of both Dio instances (tests use a fake one).
  @visibleForTesting
  set httpClientAdapter(HttpClientAdapter adapter) {
    _dio.httpClientAdapter = adapter;
    _authDio.httpClientAdapter = adapter;
  }

  static bool _isSessionExpired(DioException err) {
    final statusCode = err.response?.statusCode;
    final responseData = err.response?.data?.toString() ?? '';
    return statusCode == 401 ||
        statusCode == 403 ||
        responseData.contains('login-actions') ||
        responseData.contains('auth.bmstu.ru');
  }

  // Requests that fail together share one relogin instead of each starting its own
  Future<bool> _reloginOnce() {
    final pending = _reloginInFlight;
    if (pending != null) return pending;

    final relogin = () async {
      try {
        return await onSilentRelogin!();
      } catch (e) {
        debugPrint('[BmstuApiService] Silent relogin failed: $e');
        return false;
      }
    }();
    _reloginInFlight = relogin;
    // whenComplete always fires asynchronously, i.e. after the assignment above
    relogin.whenComplete(() {
      if (identical(_reloginInFlight, relogin)) _reloginInFlight = null;
    });
    return relogin;
  }

  bool get isAuthenticated => _isAuthenticated;

  /// Checks whether the saved session cookies are still valid, without the password.
  /// Returns the fresh profile, or null when LKS wants a new login.
  /// Network failures are thrown as [BmstuNetworkException].
  Future<UserProfile?> restoreSession() async {
    try {
      final profile = await fetchUserProfile();
      _isAuthenticated = profile != null;
      return profile;
    } on DioException catch (e) {
      _isAuthenticated = false;
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) return null;
      throw BmstuNetworkException.fromDio(e);
    }
  }

  Future<UserProfile?> _profileIfSignedIn() async {
    final profile = await fetchUserProfile();
    if (profile != null) _isAuthenticated = true;
    return profile;
  }

  /// Forgets the LKS session (logout, switching to guest mode).
  Future<void> clearSession() async {
    _isAuthenticated = false;
    try {
      await cookieJar.deleteAll();
    } catch (e) {
      debugPrint('[BmstuApiService] Failed to clear session cookies: $e');
    }
  }

  // Real-time Keycloak SSO Login
  Future<UserProfile?> login(String username, String password) async {
    try {

      // 1. Initial request to LKS login endpoint (gets redirected to sso.bmstu.ru)
      final initResp = await _authDio.get<String>(
        'https://lks.bmstu.ru/portal4/cookie/login',
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      String? ssoUrl = initResp.headers.value('location');
      if (ssoUrl == null || !ssoUrl.contains('sso.bmstu.ru')) {
        final resp2 = await _authDio.get<String>('https://lks.bmstu.ru/portal4/cookie/login');
        ssoUrl = resp2.realUri.toString();
      }

      if (ssoUrl.isEmpty || !ssoUrl.contains('sso.bmstu.ru')) {
        // LKS didn't send us to SSO: the saved session is still valid
        final current = await _profileIfSignedIn();
        if (current != null) return current;
        throw Exception('Не удалось подключиться к серверу авторизации МГТУ');
      }

      // 2. Fetch Keycloak HTML Form
      final ssoPageResp = await _authDio.get<String>(ssoUrl);
      final ssoHtml = ssoPageResp.data ?? '';

      final actionUrl = extractLoginFormAction(ssoHtml, ssoPageResp.realUri);
      if (actionUrl == null && ssoPageResp.realUri.host != 'sso.bmstu.ru') {
        // SSO remembered the student and redirected straight back to LKS, no form shown
        final current = await _profileIfSignedIn();
        if (current != null) return current;
      }
      if (actionUrl == null) {
        throw Exception('Страница входа МГТУ изменилась, вход через приложение временно недоступен');
      }

      // 3. Post Credentials to Keycloak
      final authResp = await _authDio.post(
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
        await _authDio.get(
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
        // Keycloak answered with another page of its own (password change, OTP, terms...)
        // instead of redirecting back to LKS: the session was not created
        if (bodyStr.contains('login-actions') ||
            bodyStr.contains('kc-form') ||
            (callbackUrl?.contains('login-actions') ?? false)) {
          throw Exception('Сервер авторизации МГТУ запросил дополнительное действие '
              '(например, смену пароля). Войдите один раз на lks.bmstu.ru в браузере');
        }
      }

      // 4. Verify Profile
      final profile = await fetchUserProfile();
      if (profile == null) {
        throw Exception('Неверный логин или пароль, либо ошибка сессии');
      }

      _isAuthenticated = true;
      return profile;
    } on DioException catch (e) {
      _isAuthenticated = false;
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        throw Exception('Неверный логин или пароль студента');
      }
      throw BmstuNetworkException.fromDio(e);
    } catch (e) {
      _isAuthenticated = false;
      rethrow;
    }
  }

  /// Link to the QR pass, or null when LKS doesn't give one. Never throws.
  Future<String?> _fetchQrUrl() async {
    try {
      final qrResp = await _authDio.get('$apiBase/student/qr');
      final qrData = qrResp.data is Map ? qrResp.data : null;
      final q = qrData?['data'] ?? qrData;
      return q?['qr'] as String?;
    } catch (e) {
      debugPrint('[BmstuApiService] Student QR unavailable: $e');
      return null;
    }
  }

  /// The student's photo from the official endpoint as a URL or data URI. Never throws.
  Future<String?> _fetchPhotoFromApi() async {
    try {
      final photoResp = await _authDio.get('$apiBase/student/photo');
      if (photoResp.statusCode == 200 && photoResp.data is Map) {
        final rawPhoto = (photoResp.data as Map)['photo']?.toString();
        if (rawPhoto != null && rawPhoto.isNotEmpty) {
          final isUrl = rawPhoto.startsWith('data:image') ||
              rawPhoto.startsWith('http://') ||
              rawPhoto.startsWith('https://');
          // Anything else is bare base64 of the image
          return isUrl ? rawPhoto : 'data:image/jpeg;base64,$rawPhoto';
        }
      }
    } catch (e) {
      debugPrint('[BmstuApiService] Student photo endpoint unavailable: $e');
    }
    return null;
  }

  // Fetch Student Profile from /person and /student
  Future<UserProfile?> fetchUserProfile() async {
    try {
      final personResp = await _authDio.get('$apiBase/person');
      final personData = personResp.data is Map ? personResp.data : null;
      if (personData == null) return null;

      final p = personData['data'] ?? personData;
      if (p['firstName'] == null) return null;

      // The QR pass and the photo don't depend on the student record: ask for all three
      // at once instead of one after another (this runs on every app start)
      final qrRequest = _fetchQrUrl();
      final photoRequest = _fetchPhotoFromApi();
      final studentResp = await _authDio.get('$apiBase/student');
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

      final qrUrl = await qrRequest;

      final semester = (group['semester'] as num?)?.toInt() ?? 1;
      final dormitory = p['dormitory']?.toString() == 'dormitory.true' ||
          s?['dormitory']?.toString() == 'dormitory.true';

      // 1. Primary official endpoint: GET $apiBase/student/photo
      String? photoUrl = await photoRequest;

      // 2. Scrape student photo from https://lks.bmstu.ru/profile (_img_1rxc3_40 _visible_1rxc3_45)
      if (photoUrl == null || photoUrl.isEmpty) {
        try {
          final profilePageResp = await _authDio.get('https://lks.bmstu.ru/profile');
          if (profilePageResp.statusCode == 200 && profilePageResp.data != null) {
            final scrapedPhoto = parseProfilePhotoHtml(profilePageResp.data.toString());
            if (scrapedPhoto != null && scrapedPhoto.isNotEmpty) {
              photoUrl = scrapedPhoto;
            }
          }
        } catch (e) {
          debugPrint('[BmstuApiService] Profile page photo unavailable: $e');
        }
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
    } on DioException {
      // Network failures must reach the caller, not look like "not logged in"
      rethrow;
    } catch (e) {
      debugPrint('[BmstuApiService] Failed to parse user profile: $e');
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
    } catch (e) {
      debugPrint('[BmstuApiService] Failed to load current week: $e');
    }
    return fallbackToDefault ? CurrentWeek.defaultWeek() : null;
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
            return LksParsers.schedule(sched);
          }
        }
      } catch (e) {
        debugPrint('[BmstuApiService] Private schedule failed, using public one: $e');
      }
    }

    // 2. Try public endpoint
    final pubResp = await _dio.get('$apiBase/schedules/groups/$groupUuid/public');
    if (pubResp.statusCode == 200 && pubResp.data is Map) {
      final data = pubResp.data['data'] ?? pubResp.data;
      final sched = data?['schedule'] as List?;
      if (sched != null) {
        return LksParsers.schedule(sched);
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
            return LksParsers.schedule(sched);
          }
        } else if (resp.data is List) {
          return LksParsers.schedule(resp.data as List);
        }
      }
    } on DioException catch (dioErr) {
      if (dioErr.response?.statusCode == 401 || dioErr.response?.statusCode == 403) {
        throw BmstuAuthException('Сессия устарела или требуется авторизация в ЛКС');
      }
      throw BmstuNetworkException.fromDio(dioErr);
    }

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

        return LksParsers.progress(disciplines);
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
    } on DioException catch (e) {
      throw BmstuNetworkException.fromDio(e);
    }
    return null;
  }

  // Full list of study groups from the public university structure (no auth needed).
  // About 700 KB, so it gets a longer timeout and is cached by GroupsCatalogSync.
  Future<List<GroupItem>> fetchGroupsCatalog() async {
    final resp = await _dio.get(
      '$apiBase/structure',
      options: Options(receiveTimeout: const Duration(seconds: 40)),
    );
    if (resp.statusCode == 200 && resp.data is Map<String, dynamic>) {
      return BmstuGroupsCatalog.parseStructure(resp.data as Map<String, dynamic>);
    }
    return [];
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
      throw BmstuNetworkException.fromDio(dioErr);
    }
    return [];
  }

  // Parsing lives in LksParsers; these names are kept for callers and tests
  static String? extractLoginFormAction(String html, Uri pageUri) => LksParsers.extractLoginFormAction(html, pageUri);
  static String? parseProfilePhotoHtml(String html) => LksParsers.parseProfilePhotoHtml(html);
  static List<SemesterSession> parseSessionHtml(String html) => LksParsers.parseSessionHtml(html);
  static List<SemesterSession> parseSessionJson(Map<String, dynamic> json) => LksParsers.parseSessionJson(json);

  // Get Session Results (from official API, HTML scraping, or cache)
  Future<List<SemesterSession>> getSessionResults({
    String? stageUuid,
    bool forceRefresh = false,
  }) async {
    const cacheKey = 'bmstu_session_results_cache';
    final targetStage = (stageUuid != null && stageUuid.isNotEmpty) ? stageUuid : _lastStageUuid;

    // 1. If not forcing refresh, try cache first if available
    if (!forceRefresh) {
      final cachedJson = await CacheStore.instance.read(cacheKey);
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
              unawaited(_fetchAndCacheSessionResults(cacheKey, stageUuid: targetStage)
                  .catchError((Object e) {
                debugPrint('[BmstuApiService] Background session refresh failed: $e');
                return <SemesterSession>[];
              }));
            }
            return cachedList;
          }
        } catch (e) {
          debugPrint('[BmstuApiService] Corrupted session cache ignored: $e');
        }
      }
    }

    // 2. Fetch live data
    try {
      final liveSessions = await _fetchAndCacheSessionResults(cacheKey, stageUuid: targetStage);
      if (liveSessions.isNotEmpty) return liveSessions;
    } catch (e) {
      // 3. On error, fallback to cache
      final cachedJson = await CacheStore.instance.read(cacheKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(cachedJson) as List;
          return decoded
              .whereType<Map<String, dynamic>>()
              .map((s) => SemesterSession.fromJson(s))
              .toList();
        } catch (cacheErr) {
          debugPrint('[BmstuApiService] Corrupted session cache ignored: $cacheErr');
        }
      }
      rethrow;
    }

    return [];
  }

  Future<List<SemesterSession>> _fetchAndCacheSessionResults(
    String cacheKey, {
    String? stageUuid,
  }) async {
    var targetStage = (stageUuid != null && stageUuid.isNotEmpty) ? stageUuid : _lastStageUuid;
    // If every source fails, the caller must get the error (and fall back to cache),
    // not an empty list that looks like "no session results"
    Object? lastError;

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
      } catch (e) {
        lastError = e;
      }
    }

    // 1. Primary official JSON API endpoint
    if (targetStage != null && targetStage.isNotEmpty) {
      try {
        final resp = await _dio.get('$apiBase/student/$targetStage/sessions');
        if (resp.statusCode == 200 && resp.data is Map) {
          final sessions = parseSessionJson(Map<String, dynamic>.from(resp.data as Map));
          if (sessions.isNotEmpty) {
            final jsonList = sessions.map((s) => s.toJson()).toList();
            await CacheStore.instance.write(cacheKey, jsonEncode(jsonList));
            return sessions;
          }
        }
      } catch (e) {
        debugPrint('[BmstuApiService] Sessions API failed, trying the LKS page: $e');
        lastError = e;
      }
    }

    // 2. Fallback to HTML scraping
    try {
      final resp = await _dio.get('https://lks.bmstu.ru/session');
      if (resp.statusCode == 200 && resp.data != null) {
        // LKS answered: an empty page means "no results yet", not a failure
        lastError = null;
        final html = resp.data.toString();
        final sessions = parseSessionHtml(html);
        if (sessions.isNotEmpty) {
          final jsonList = sessions.map((s) => s.toJson()).toList();
          await CacheStore.instance.write(cacheKey, jsonEncode(jsonList));
          return sessions;
        }
      }
    } catch (e) {
      lastError = e;
    }

    if (lastError is DioException) throw BmstuNetworkException.fromDio(lastError);
    if (lastError != null) throw lastError;
    return [];
  }
}
