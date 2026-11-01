import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bmstu_neo/demo/demo_api_service.dart';
import 'package:bmstu_neo/providers/auth_provider.dart';
import 'package:bmstu_neo/services/bmstu_groups_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<AuthProvider> signedIn() async {
    final auth = AuthProvider(apiService: DemoApiService(), authStorage: DemoAuthStorage());
    await auth.checkSavedAuth();
    return auth;
  }

  test('The primary group is the student\'s own until they choose another', () async {
    final auth = await signedIn();
    expect(auth.currentGroupTitle, 'РК6-31Б');
    expect(auth.hasPrimaryOverride, isFalse);

    await auth.setPrimaryGroup(const GroupItem(title: 'РК6-32Б', uuid: 'other'));
    expect(auth.currentGroupUuid, 'other');
    expect(auth.ownGroupTitle, 'РК6-31Б');
    final saved = jsonDecode((await SharedPreferences.getInstance()).getString(AuthProvider.primaryGroupKey)!);
    expect(saved['title'], 'РК6-32Б');

    // Picking the own group again is the same as resetting
    await auth.setPrimaryGroup(GroupItem(title: 'РК6-31Б', uuid: auth.ownGroupUuid));
    expect(auth.hasPrimaryOverride, isFalse);
    expect((await SharedPreferences.getInstance()).getString(AuthProvider.primaryGroupKey), isNull);
  });

  test('The choice survives a restart and is forgotten on logout', () async {
    final first = await signedIn();
    await first.setPrimaryGroup(const GroupItem(title: 'РК6-32Б', uuid: 'other'));

    final second = await signedIn();
    expect(second.currentGroupTitle, 'РК6-32Б');

    await second.logout();
    expect((await SharedPreferences.getInstance()).getString(AuthProvider.primaryGroupKey), isNull);
    expect(second.hasPrimaryOverride, isFalse);
  });
}
