import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/schedule_lesson.dart';
import '../providers/auth_provider.dart';
import '../providers/schedule_provider.dart';
import '../services/bmstu_api_service.dart';
import 'login_screen.dart';

class TeacherScheduleScreen extends StatefulWidget {
  final String? teacherUuid;
  final String? teacherName;
  final BmstuApiService? apiService;

  const TeacherScheduleScreen({
    super.key,
    this.teacherUuid,
    this.teacherName,
    this.apiService,
  });

  static const List<String> daysShort = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ'];
  static const List<String> daysFull = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
  ];

  @override
  State<TeacherScheduleScreen> createState() => _TeacherScheduleScreenState();
}

class _TeacherScheduleScreenState extends State<TeacherScheduleScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final PageController _dayPageController;
  Timer? _debounceTimer;

  String? _currentUuid;
  String? _currentName;
  bool _isSearching = false;
  bool _isSearchLoading = false;
  List<TeacherSearchItem> _searchResults = [];

  bool _isLoading = false;
  bool _isAuthRequired = false;
  bool _isGuestLimited = false;
  String? _errorMessage;
  List<ScheduleLesson> _lessons = [];

  int _selectedDay = 1;
  String _weekFilter = 'all'; // 'all' | 'ch' | 'zn'

  BmstuApiService get _apiService =>
      widget.apiService ?? context.read<AuthProvider>().apiService;

  @override
  void initState() {
    super.initState();
    final todayWeekday = DateTime.now().weekday;
    _selectedDay = todayWeekday.clamp(1, 6);
    _dayPageController = PageController(initialPage: _selectedDay - 1);

    _currentUuid = widget.teacherUuid;
    _currentName = widget.teacherName;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_currentUuid != null && _currentUuid!.isNotEmpty) {
        _loadCachedAndFetch();
      } else if (_currentName != null && _currentName!.isNotEmpty) {
        _resolveTeacherByName(_currentName!);
      } else {
        setState(() {
          _isSearching = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _dayPageController.dispose();
    super.dispose();
  }

  Future<void> _loadCachedAndFetch() async {
    if (_currentUuid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('teacher_sched_${_currentUuid!}');
      if (cachedJson != null && mounted) {
        final decoded = jsonDecode(cachedJson) as List;
        setState(() {
          _lessons = decoded
              .map((e) => ScheduleLesson.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (_) {}
    await _fetchSchedule();
  }

  Future<void> _resolveTeacherByName(String name, {bool isRetry = false}) async {
    final auth = context.read<AuthProvider>();

    if (auth.isGuest || !auth.isFullAuth) {
      // In guest mode, find within the loaded schedule
      final sched = context.read<ScheduleProvider>();
      final localLessons = sched.allLessons.where((l) {
        return l.teachers.any((t) =>
            t.fullName.toLowerCase().contains(name.toLowerCase()) ||
            t.lastName.toLowerCase().contains(name.toLowerCase()));
      }).toList();

      if (localLessons.isNotEmpty) {
        final matchTeacher = localLessons
            .expand((l) => l.teachers)
            .firstWhere((t) =>
                t.fullName.toLowerCase().contains(name.toLowerCase()) ||
                t.lastName.toLowerCase().contains(name.toLowerCase()));
        setState(() {
          _currentUuid = matchTeacher.uuid ?? 'local_${matchTeacher.lastName}';
          _currentName = matchTeacher.fullName;
          _lessons = localLessons;
          _isLoading = false;
          _isGuestLimited = true;
        });
        return;
      }

      setState(() {
        _isLoading = false;
        _isAuthRequired = true;
        _isSearching = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isAuthRequired = false;
    });

    try {
      final searchResults = await _apiService.searchTeachersOnline(name);
      if (searchResults.isNotEmpty && mounted) {
        final match = searchResults.first;
        setState(() {
          _currentUuid = match.uuid;
          _currentName = match.title;
        });
        await _loadCachedAndFetch();
      } else if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Преподаватель не найден в системе расписания';
          _isSearching = true;
        });
      }
    } on BmstuAuthException catch (_) {
      if (!isRetry && mounted) {
        final reloggedIn = await auth.reloginSilently();
        if (reloggedIn && mounted) {
          return _resolveTeacherByName(name, isRetry: true);
        }
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Сессия устарела. Требуется повторный вход в ЛКС.';
          _isAuthRequired = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSearching = true;
        });
      }
    }
  }

  Future<void> _fetchSchedule({bool isRetry = false}) async {
    if (_currentUuid == null || _currentUuid!.isEmpty) return;

    final auth = context.read<AuthProvider>();

    // If guest mode, extract lessons from current group
    if (auth.isGuest || !auth.isFullAuth) {
      final sched = context.read<ScheduleProvider>();
      final localLessons = sched.allLessons.where((l) {
        return l.teachers.any((t) =>
            (t.uuid != null && t.uuid == _currentUuid) ||
            t.fullName.toLowerCase() == (_currentName ?? '').toLowerCase() ||
            t.formattedName.toLowerCase() == (_currentName ?? '').toLowerCase() ||
            (_currentName != null && t.lastName.isNotEmpty && _currentName!.contains(t.lastName)));
      }).toList();

      setState(() {
        _isLoading = false;
        _lessons = localLessons;
        _isAuthRequired = localLessons.isEmpty;
        _isGuestLimited = localLessons.isNotEmpty;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isAuthRequired = false;
    });

    try {
      final fetched = await _apiService.getTeacherSchedule(_currentUuid!);
      if (mounted) {
        setState(() {
          _lessons = fetched;
          _isLoading = false;
          _isAuthRequired = false;
          _isGuestLimited = false;
        });

        // Save to cache
        try {
          final prefs = await SharedPreferences.getInstance();
          final jsonString = jsonEncode(fetched.map((l) => l.toJson()).toList());
          await prefs.setString('teacher_sched_${_currentUuid!}', jsonString);
        } catch (_) {}
      }
    } on BmstuAuthException catch (_) {
      if (!isRetry && mounted) {
        final reloggedIn = await auth.reloginSilently();
        if (reloggedIn && mounted) {
          return _fetchSchedule(isRetry: true);
        }
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Сессия устарела. Требуется повторный вход в ЛКС.';
          _isAuthRequired = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_lessons.isEmpty) {
            _errorMessage = 'Не удалось загрузить расписание. Проверьте сеть.';
          }
        });
      }
    }
  }

  void _onSearchQueryChanged(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearchLoading = false;
      });
      return;
    }

    setState(() {
      _isSearchLoading = true;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      final auth = context.read<AuthProvider>();
      if (auth.isGuest || !auth.isFullAuth) {
        // Search in current group's schedule
        final sched = context.read<ScheduleProvider>();
        final teachersMap = <String, TeacherSearchItem>{};
        for (final l in sched.allLessons) {
          for (final t in l.teachers) {
            if (t.fullName.toLowerCase().contains(trimmed.toLowerCase()) ||
                t.lastName.toLowerCase().contains(trimmed.toLowerCase())) {
              teachersMap[t.fullName] = TeacherSearchItem(
                title: t.fullName,
                uuid: t.uuid ?? 'local_${t.lastName}',
              );
            }
          }
        }
        if (mounted) {
          setState(() {
            _searchResults = teachersMap.values.toList();
            _isSearchLoading = false;
          });
        }
        return;
      }

      try {
        final results = await _apiService.searchTeachersOnline(trimmed);
        if (mounted) {
          setState(() {
            _searchResults = results;
            _isSearchLoading = false;
          });
        }
      } on BmstuAuthException catch (_) {
        if (mounted) {
          final reloggedIn = await auth.reloginSilently();
          if (reloggedIn && mounted) {
            final retryResults = await _apiService.searchTeachersOnline(trimmed);
            if (mounted) {
              setState(() {
                _searchResults = retryResults;
                _isSearchLoading = false;
              });
            }
            return;
          }
          setState(() {
            _isSearchLoading = false;
            _isAuthRequired = true;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _isSearchLoading = false;
          });
        }
      }
    });
  }

  void _selectTeacher(TeacherSearchItem item) {
    setState(() {
      _currentUuid = item.uuid;
      _currentName = item.title;
      _isSearching = false;
      _searchResults = [];
      _searchController.clear();
    });
    _loadCachedAndFetch();
  }

  List<ScheduleLesson> _getLessonsForDay(int day) {
    return _lessons.where((l) {
      if (l.day != day) return false;
      if (_weekFilter == 'all') return true;
      if (_weekFilter == 'ch') return l.matchesWeek(isNumeratorWeek: true);
      if (_weekFilter == 'zn') return l.matchesWeek(isNumeratorWeek: false);
      return true;
    }).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'lecture':
      case 'лекция':
        return const Color(0xFF3B82F6);
      case 'seminar':
      case 'семинар':
        return const Color(0xFF10B981);
      case 'lab':
      case 'лабораторная':
      case 'лабораторная работа':
        return const Color(0xFFF59E0B);
      case 'military':
      case 'военная кафедра':
      case 'вк':
        return const Color(0xFF15803D);
      case 'elective':
      case 'факультатив':
        return const Color(0xFF0EA5E9);
      case 'consultation':
      case 'консультация':
        return const Color(0xFFE11D48);
      default:
        return const Color(0xFF8B5CF6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: _isSearching ? 0 : null,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Поиск преподавателя (Фамилия И.О.)',
                  border: InputBorder.none,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchQueryChanged('');
                          },
                        )
                      : null,
                ),
                onChanged: _onSearchQueryChanged,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Расписание преподавателя',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Text(
                    _currentName ?? 'Выбор преподавателя',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
        actions: [
          if (!_isSearching) ...[
            IconButton(
              icon: const Icon(Icons.search_rounded),
              tooltip: 'Найти другого преподавателя',
              onPressed: () {
                setState(() {
                  _isSearching = true;
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Обновить',
              onPressed: _isLoading ? null : () => _fetchSchedule(),
            ),
          ] else if (_currentUuid != null) ...[
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Закрыть поиск',
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchController.clear();
                  _searchResults = [];
                });
              },
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: _isSearching
          ? _buildSearchResultsView(theme, isDark)
          : _buildScheduleView(theme, isDark),
    );
  }

  Widget _buildSearchResultsView(ThemeData theme, bool isDark) {
    if (_isSearchLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchController.text.trim().isEmpty) {
      final auth = context.read<AuthProvider>();
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_search_rounded,
                size: 64,
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'Поиск по преподавателям',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                auth.isGuest
                    ? 'В гостевом режиме доступен поиск по преподавателям текущей группы. Для поиска по всем преподавателям МГТУ войдите в аккаунт ЛКС.'
                    : 'Введите фамилию преподавателя МГТУ им. Баумана для просмотра его полного расписания',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (auth.isGuest) ...[
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Войти в ЛКС'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 56,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'Преподаватель не найден',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Попробуйте изменить запрос или ввести только фамилию',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _searchResults.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _searchResults[index];
        return Material(
          color: isDark
              ? theme.colorScheme.surfaceContainer
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _selectTeacher(item),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.person_outline_rounded,
                      size: 20,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Преподаватель МГТУ',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildScheduleView(ThemeData theme, bool isDark) {
    if (_isLoading && _lessons.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isAuthRequired && _lessons.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Требуется авторизация в ЛКС',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Расписание преподавателей защищено политикой безопасности МГТУ им. Баумана и доступно только после входа в аккаунт ЛКС.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                icon: const Icon(Icons.login_rounded),
                label: const Text('Войти в аккаунт ЛКС'),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null && _lessons.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 56,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Ошибка загрузки',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => _fetchSchedule(),
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Guest mode informational notice
        if (_isGuestLimited)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Показаны пары в вашей группе. Для всех групп войдите в ЛКС.',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                  child: const Text('Войти'),
                ),
              ],
            ),
          ),

        // Day selector tab bar
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark
                ? theme.colorScheme.surfaceContainer
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: List.generate(6, (index) {
              final dayNum = index + 1;
              final isSelected = _selectedDay == dayNum;
              final isToday = DateTime.now().weekday == dayNum;

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDay = dayNum;
                    });
                    _dayPageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          TeacherScheduleScreen.daysShort[index],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: isSelected
                                ? theme.colorScheme.onPrimary
                                : (isToday
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                        if (isToday)
                          Container(
                            margin: const EdgeInsets.only(top: 3),
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),

        // Week filter chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              _buildFilterChip('all', 'Все недели', theme),
              const SizedBox(width: 8),
              _buildFilterChip('ch', 'Числитель', theme),
              const SizedBox(width: 8),
              _buildFilterChip('zn', 'Знаменатель', theme),
            ],
          ),
        ),

        const SizedBox(height: 4),

        // Day Pages
        Expanded(
          child: PageView.builder(
            controller: _dayPageController,
            itemCount: 6,
            onPageChanged: (page) {
              setState(() {
                _selectedDay = page + 1;
              });
            },
            itemBuilder: (context, index) {
              final dayNum = index + 1;
              final dayLessons = _getLessonsForDay(dayNum);

              if (dayLessons.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.event_busy_rounded,
                          size: 56,
                          color: theme.colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Пар нет',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'В этот день у преподавателя нет занятий',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () => _fetchSchedule(),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: dayLessons.length,
                  itemBuilder: (context, lIdx) {
                    final lesson = dayLessons[lIdx];
                    return _buildTeacherLessonCard(lesson, theme, isDark);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String key, String label, ThemeData theme) {
    final isSelected = _weekFilter == key;
    return FilterChip(
      selected: isSelected,
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurfaceVariant,
      ),
      selectedColor: theme.colorScheme.primaryContainer,
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (_) {
        setState(() {
          _weekFilter = key;
        });
      },
    );
  }

  Widget _buildTeacherLessonCard(
    ScheduleLesson lesson,
    ThemeData theme,
    bool isDark,
  ) {
    final typeColor = _getTypeColor(lesson.actType);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainer
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Pair number, time, and type badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? theme.colorScheme.surfaceContainerHigh
                        : theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    lesson.time > 0 ? '${lesson.time} пара' : 'Занятие',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${lesson.startTime} — ${lesson.endTime}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    lesson.actTypeTitle,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: typeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Discipline title
            Text(
              lesson.disciplineTitle,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 10),

            // Audience & Group row
            Row(
              children: [
                // Classroom
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.meeting_room_outlined,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          lesson.audiencesFormatted,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                // Group / Stream being taught
                if (lesson.streamName != null && lesson.streamName!.isNotEmpty)
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.groups_rounded,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            lesson.streamName!,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            if (!lesson.isEveryWeek) ...[
              const SizedBox(height: 8),
              Text(
                'Периодичность: ${lesson.weekTitle}',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
