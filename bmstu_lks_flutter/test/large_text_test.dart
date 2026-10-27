import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bmstu_neo/models/discipline_progress.dart';
import 'package:bmstu_neo/models/session_result.dart';
import 'package:bmstu_neo/models/user_profile.dart';
import 'package:bmstu_neo/providers/auth_provider.dart';
import 'package:bmstu_neo/providers/progress_provider.dart';
import 'package:bmstu_neo/providers/theme_provider.dart';
import 'package:bmstu_neo/screens/login_screen.dart';
import 'package:bmstu_neo/services/auth_storage.dart';
import 'package:bmstu_neo/services/bmstu_api_service.dart';
import 'package:bmstu_neo/widgets/grades/discipline_card.dart';
import 'package:bmstu_neo/widgets/profile_session_card.dart';

// Logs in without network and serves fixed session results
class FakeSessionApi extends BmstuApiService {
  @override
  Future<UserProfile?> login(String username, String password) async => UserProfile(
        lastName: 'Константинопольский',
        firstName: 'Александр',
        middleName: 'Алексеевич',
        groupTitle: 'РК5-32Б',
        groupUuid: 'group-1',
        stageUuid: 'stage-1',
      );

  @override
  Future<List<SemesterSession>> getSessionResults({String? stageUuid, bool forceRefresh = false}) async => const [
        SemesterSession(
          semesterTitle: 'Семестр 2',
          semesterNumber: 2,
          disciplines: [
            SessionDiscipline(title: 'Физика', department: 'ФН4', controlType: 'Экз', hours: 144, grade: 'Удовлетворительно'),
            SessionDiscipline(
              title: 'Интегралы и дифференциальные уравнения',
              department: 'ФН2',
              controlType: 'Экз',
              hours: 144,
              grade: 'Не аттестован',
            ),
          ],
        ),
      ];
}

/// Renders [child] on a narrow phone with the system text size set to [scale].
Future<void> _pumpAt(WidgetTester tester, double scale, Widget child) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(size: const Size(360, 780), textScaler: TextScaler.linear(scale)),
    child: child,
  ));
  await tester.pumpAndSettle();
}

// Measure with the real app font: the default test font draws every glyph 1 em
// wide and would report overflows that never happen on a phone
Future<void> _loadAppFont() async {
  final loader = FontLoader(appFontFamily);
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold', 'Black']) {
    loader.addFont(rootBundle.load('assets/fonts/Onest-$w.ttf'));
  }
  await loader.load();
}

final _theme = ThemeData(useMaterial3: true, fontFamily: appFontFamily);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadAppFont);

  for (final scale in [1.0, 1.5, 2.0]) {
    group('System text size ×$scale on a 360 pt wide phone', () {
      testWidgets('Discipline card', (tester) async {
        ControlEvent ev(String type, int week, String? stage, int i) => ControlEvent(
              type: type,
              title: '$type-$i',
              week: week,
              stage: stage,
              disciplineTitle: 'Сопротивление материалов',
              controlIndex: i,
            );
        final events = [ev('ДЗ', 4, '1', 1), ev('РК', 5, '2', 1), ev('ДЗ', 9, '1', 2), ev('РК', 10, null, 2)];
        await _pumpAt(
          tester,
          scale,
          MaterialApp(
            theme: _theme,
            home: Scaffold(
              body: SingleChildScrollView(
                child: DisciplineCard(
                  disc: DisciplineProgress(
                    title: 'Сопротивление материалов и строительная механика',
                    points: const {},
                    controls: events,
                  ),
                  events: events,
                  currentWeek: 8,
                  isDark: false,
                ),
              ),
            ),
          ),
        );
      });

      testWidgets('Profile session card', (tester) async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        final auth = AuthProvider(apiService: FakeSessionApi(), authStorage: AuthStorage());
        await tester.runAsync(() => auth.login('student', 'secret', rememberMe: false));

        await _pumpAt(
          tester,
          scale,
          ChangeNotifierProvider<AuthProvider>.value(
            value: auth,
            child: MaterialApp(theme: _theme, home: const Scaffold(body: SingleChildScrollView(child: ProfileSessionCard()))),
          ),
        );
      });

      testWidgets('Login screen', (tester) async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        final auth = AuthProvider(apiService: FakeSessionApi(), authStorage: AuthStorage());
        await _pumpAt(
          tester,
          scale,
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthProvider>.value(value: auth),
              ChangeNotifierProvider(create: (_) => ProgressProvider(apiService: BmstuApiService())),
            ],
            child: MaterialApp(theme: _theme, home: const LoginScreen()),
          ),
        );
      });
    });
  }
}
