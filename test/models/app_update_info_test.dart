import 'package:flutter_test/flutter_test.dart';
import 'package:animemaster/src/models/app_update_info.dart';

void main() {
  group('AppUpdateInfo.fromJson', () {
    test('parses complete manifest JSON', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'version': '2.4.0',
        'build': 35,
        'apkUrl': 'https://example.com/app.apk',
        'notes': '- Bug fixes\n- New features',
        'publishedAt': '2026-05-01T12:00:00+08:00',
        'forceUpdate': true,
      };

      final AppUpdateInfo info = AppUpdateInfo.fromJson(json);

      expect(info.version, '2.4.0');
      expect(info.buildNumber, 35);
      expect(info.apkUrl, 'https://example.com/app.apk');
      expect(info.changeLog, '- Bug fixes\n- New features');
      expect(info.publishedAt, '2026-05-01T12:00:00+08:00');
      expect(info.forceUpdate, true);
    });

    test('parses changelog from array format', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'version': '1.0',
        'build': 1,
        'apkUrl': 'https://x.com/a.apk',
        'notes': <String>['Fix crash', 'Add dark mode'],
        'publishedAt': '',
      };

      final AppUpdateInfo info = AppUpdateInfo.fromJson(json);

      expect(info.changeLog, 'Fix crash\nAdd dark mode');
    });

    test('handles alternate field names (changeLog, url, buildNumber)', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'version': '1.0',
        'buildNumber': '10',
        'url': 'https://x.com/a.apk',
        'changeLog': 'Some notes',
        'publishedAt': '',
      };

      final AppUpdateInfo info = AppUpdateInfo.fromJson(json);

      expect(info.buildNumber, 10);
      expect(info.apkUrl, 'https://x.com/a.apk');
      expect(info.changeLog, 'Some notes');
    });

    test('handles missing optional fields', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'version': '',
        'apkUrl': '',
      };

      final AppUpdateInfo info = AppUpdateInfo.fromJson(json);

      expect(info.version, '');
      expect(info.buildNumber, 0);
      expect(info.apkUrl, '');
      expect(info.changeLog, '');
    });

    test('parses apkUrls from downloads alias', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'version': '1.0',
        'apkUrl': '',
        'downloads': <String, dynamic>{
          'android-arm64': 'https://x.com/arm64.apk',
          'android-arm': 'https://x.com/arm.apk',
        },
      };

      final AppUpdateInfo info = AppUpdateInfo.fromJson(json);

      expect(info.apkUrls['android-arm64'], 'https://x.com/arm64.apk');
      expect(info.apkUrls['android-arm'], 'https://x.com/arm.apk');
    });

    test('parses sha256 map', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'version': '1.0',
        'apkUrl': '',
        'sha256': <String, dynamic>{
          'universal': 'abc123def456',
          'android-arm64': '789ghi012jkl',
        },
      };

      final AppUpdateInfo info = AppUpdateInfo.fromJson(json);

      expect(info.sha256Map['universal'], 'abc123def456');
      expect(info.sha256Map['android-arm64'], '789ghi012jkl');
    });
  });
}
