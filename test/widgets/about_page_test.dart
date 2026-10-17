import 'package:animemaster/src/config/app_release.dart';
import 'package:animemaster/src/providers/settings_provider.dart';
import 'package:animemaster/src/screens/about_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('about shows the build suffix and current release notes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    PackageInfo.setMockInitialValues(
      appName: 'AnimeMaster',
      packageName: 'com.animemaster.app',
      version: AppRelease.version,
      buildNumber: AppRelease.build.toString(),
      buildSignature: 'test',
    );
    final settings = SettingsProvider();
    await settings.initialize();
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: const MaterialApp(home: AboutPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('${AppRelease.version}+${AppRelease.build}'),
      findsOneWidget,
    );
    expect(settings.coreEngineVersion, contains('v${AppRelease.version}'));
    await tester.scrollUntilVisible(find.text('v${AppRelease.version}'), 250);
    await tester.pumpAndSettle();
    expect(find.text('v${AppRelease.version}'), findsOneWidget);
    for (final note in AppRelease.notes) {
      expect(find.text(note), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
