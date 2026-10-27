import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:bmstu_neo/main.dart';
import 'package:bmstu_neo/services/auth_storage.dart';
import 'package:bmstu_neo/services/bmstu_api_service.dart';
import 'package:bmstu_neo/providers/auth_provider.dart';
import 'package:bmstu_neo/providers/schedule_provider.dart';
import 'package:bmstu_neo/providers/progress_provider.dart';
import 'package:bmstu_neo/providers/fv_provider.dart';

void main() {
  testWidgets('App basic smoke test', (WidgetTester tester) async {
    final authStorage = AuthStorage();
    final apiService = BmstuApiService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuthProvider(apiService: apiService, authStorage: authStorage),
          ),
          ChangeNotifierProvider(
            create: (_) => ScheduleProvider(apiService: apiService),
          ),
          ChangeNotifierProvider(
            create: (_) => ProgressProvider(apiService: apiService),
          ),
          ChangeNotifierProvider(
            create: (_) => FvProvider(apiService: apiService),
          ),
        ],
        child: const BmstuApp(),
      ),
    );

    expect(find.byType(BmstuApp), findsOneWidget);
  });
}
