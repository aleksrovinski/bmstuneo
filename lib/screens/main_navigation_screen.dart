import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/progress_provider.dart';
import '../providers/fv_provider.dart';
import '../providers/mail_provider.dart';
import 'home_screen.dart';
import 'schedule_screen.dart';
import 'grades_screen.dart';
import 'fv_screen.dart';
import 'profile_screen.dart';
import 'login_screen.dart';
import '../models/mail_message.dart';
import '../services/app_notifications.dart';
import '../services/notification_target.dart';
import '../services/widget_sync_service.dart';
import '../widgets/app_update_dialog.dart';
import 'mail_message_screen.dart';
import 'mail_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _hasInitialLoaded = false;
  int _loadedForSession = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppNotifications.tapped.addListener(_onNotificationTapped);
    // The notification that launched the app arrived before this screen existed
    WidgetsBinding.instance.addPostFrameCallback((_) => _onNotificationTapped());
  }

  @override
  void dispose() {
    AppNotifications.tapped.removeListener(_onNotificationTapped);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Opens the screen the tapped notification is about.
  void _onNotificationTapped() {
    final target = AppNotifications.tapped.value;
    if (target == null || !mounted) return;
    AppNotifications.tapped.value = null;
    // Whatever was open on top (a letter, settings) gives way to the notification
    Navigator.of(context).popUntil((route) => route.isFirst);

    switch (target.kind) {
      case NotificationKind.progress:
        if (target.discipline.isNotEmpty) context.read<ProgressProvider>().setSearchQuery(target.discipline);
        _onDestinationSelected(1);
      case NotificationKind.mail:
        _openMail(target);
    }
  }

  Future<void> _openMail(NotificationTarget target) async {
    final mail = context.read<MailProvider>();
    unawaited(MailScreen.open(context));
    final uid = target.uid;
    if (uid == null) return;
    // On a cold start the saved mail login is still being restored
    await mail.restore();
    if (!mounted || mail.status != MailStatus.ready) return;
    unawaited(MailMessageScreen.open(
      context,
      mailbox: target.mailbox,
      summary: MailSummary(uid: uid, from: target.from, subject: target.subject),
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || state == AppLifecycleState.paused) {
      final sched = context.read<ScheduleProvider>();
      if (sched.allLessons.isNotEmpty) {
        WidgetSyncService.updateScheduleWidget(scheduleProvider: sched);
      }
    }
    // Fresh unread count for the mail badge after the app was in the background
    if (state == AppLifecycleState.resumed) {
      context.read<MailProvider?>()?.refreshFolders();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasInitialLoaded) {
      _hasInitialLoaded = true;
      _loadedForSession = context.read<AuthProvider>().sessionGeneration;
      _triggerInitialDataLoad();
      // Android APK from the website: offer a newer build once the first screen is up
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AppUpdateDialog.maybeShow(context);
      });
    }
  }

  String? _loadedGroupUuid;

  void _loadPrimarySchedule(AuthProvider auth) {
    _loadedGroupUuid = auth.currentGroupUuid;
    if (auth.currentGroupUuid.isNotEmpty) {
      context.read<ScheduleProvider>().loadSchedule(
        groupUuid: auth.currentGroupUuid,
        groupTitle: auth.currentGroupTitle,
      );
    }
  }

  // The primary group changed in settings (or the guest picked another): reload it
  void _reloadOnPrimaryGroupChange(AuthProvider auth) {
    if (_loadedGroupUuid == null || auth.currentGroupUuid == _loadedGroupUuid) return;
    _loadedGroupUuid = auth.currentGroupUuid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadPrimarySchedule(context.read<AuthProvider>());
    });
  }

  void _triggerInitialDataLoad() {
    final auth = context.read<AuthProvider>();
    final prog = context.read<ProgressProvider>();
    final fv = context.read<FvProvider>();

    // Load Schedule
    _loadPrimarySchedule(auth);

    // Load Progress and FV if full auth
    if (auth.isFullAuth && auth.userProfile?.stageUuid != null) {
      prog.loadProgress(auth.userProfile!.stageUuid);
      fv.loadFv(auth.userProfile!.stageUuid);
    } else if (auth.isGuest) {
      fv.loadGuestSample();
    }
  }

  void _onDestinationSelected(int index) {
    if (_currentIndex == index) return;
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
  }

  // A (re)login happened after the first load: data that failed while the session
  // was expired (progress, PE, session results) is fetched again
  void _reloadAfterNewSession(int generation) {
    if (generation == _loadedForSession) return;
    _loadedForSession = generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _triggerInitialDataLoad();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final isDark = theme.brightness == Brightness.dark;
    final auth = context.watch<AuthProvider>();
    _reloadAfterNewSession(auth.sessionGeneration);
    _reloadOnPrimaryGroupChange(auth);
    final showReauth = auth.needsLogin && auth.isFullAuth;

    final pages = [
      HomeScreen(
        onOpenGrades: () => _onDestinationSelected(1),
        onOpenSchedule: () => _onDestinationSelected(2),
        onOpenFv: () => _onDestinationSelected(3),
      ),
      const GradesScreen(),
      const ScheduleScreen(),
      const FvScreen(),
      const ProfileScreen(),
    ];

    const destinations = [
      NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Главная'),
      NavigationDestination(
        icon: Icon(Icons.school_outlined),
        selectedIcon: Icon(Icons.school_rounded),
        label: 'Прогресс',
      ),
      NavigationDestination(
        icon: Icon(Icons.calendar_month_outlined),
        selectedIcon: Icon(Icons.calendar_month_rounded),
        label: 'Расписание',
      ),
      NavigationDestination(
        icon: Icon(Icons.fitness_center_outlined),
        selectedIcon: Icon(Icons.fitness_center_rounded),
        label: 'ФКиС',
      ),
      NavigationDestination(
        icon: Icon(Icons.person_outline_rounded),
        selectedIcon: Icon(Icons.person_rounded),
        label: 'Профиль',
      ),
    ];

    return Scaffold(
      extendBody: false,
      body: Column(
        children: [
          if (showReauth) const _ReauthBanner(),
          Expanded(
            // The banner already sits under the status bar
            child: MediaQuery.removePadding(
              context: context,
              removeTop: showReauth,
              child: IndexedStack(index: _currentIndex, children: pages),
            ),
          ),
        ],
      ),
      bottomNavigationBar: isIOS
          ? Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xF01C1C1E) : const Color(0xF5FFFFFF),
                border: Border(
                  top: BorderSide(color: isDark ? const Color(0x33FFFFFF) : const Color(0x28000000), width: 0.5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark ? Colors.black.withValues(alpha: 0.35) : Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: NavigationBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                selectedIndex: _currentIndex,
                onDestinationSelected: _onDestinationSelected,
                destinations: destinations,
              ),
            )
          : Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4), width: 1),
                ),
              ),
              child: NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: _onDestinationSelected,
                destinations: destinations,
              ),
            ),
    );
  }
}

/// Shown while the cached profile can't be refreshed because LKS needs the password again.
class _ReauthBanner extends StatelessWidget {
  const _ReauthBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(Icons.lock_clock_rounded, color: scheme.onErrorContainer, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Сессия ЛКС истекла — показаны сохранённые данные',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onErrorContainer),
                ),
              ),
              TextButton(
                onPressed: () => LoginScreen.showReauth(context),
                style: TextButton.styleFrom(foregroundColor: scheme.onErrorContainer),
                child: const Text('Войти', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
