import 'package:flutter_test/flutter_test.dart';
import 'package:animemaster/src/services/app_update_service.dart';
import 'package:animemaster/src/models/app_update_info.dart';

void main() {
  late AppUpdateService service;

  setUp(() {
    service = const AppUpdateService();
  });

  group('AppUpdateService package verification', () {
    test('resolves universal package and checksum on unsupported ABI', () {
      final AppUpdateInfo info = AppUpdateInfo.fromJson(<String, dynamic>{
        'version': '2.4.1',
        'build': 2046,
        'apkUrl': 'https://example.com/fallback.apk',
        'downloads': <String, dynamic>{
          'universal': 'https://example.com/universal.apk',
        },
        'sha256': <String, dynamic>{'universal': 'a' * 64},
      });

      expect(
        service.resolveDownloadUrl(info),
        'https://example.com/universal.apk',
      );
      expect(service.resolveSha256(info), 'a' * 64);
    });

    test('accepts only complete SHA-256 values', () {
      expect(service.isValidSha256('A1' * 32), isTrue);
      expect(service.isValidSha256('abc123'), isFalse);
      expect(service.isValidSha256('g' * 64), isFalse);
    });

    test(
      'falls back to the legacy package URL without inventing a checksum',
      () {
        final AppUpdateInfo info = AppUpdateInfo.fromJson(<String, dynamic>{
          'version': '2.4.1',
          'build': 2046,
          'apkUrl': 'https://example.com/fallback.apk',
        });

        expect(
          service.resolveDownloadUrl(info),
          'https://example.com/fallback.apk',
        );
        expect(service.resolveSha256(info), isNull);
      },
    );

    test('compares semantic versions and build numbers safely', () {
      expect(
        service.debugIsRemoteNewer(
          localVersion: '2.4.1',
          localBuild: 2045,
          remoteVersion: '2.4.1',
          remoteBuild: 2046,
        ),
        isTrue,
      );
      expect(
        service.debugIsRemoteNewer(
          localVersion: '2.4.1',
          localBuild: 2046,
          remoteVersion: '2.4.0',
          remoteBuild: 9999,
        ),
        isFalse,
      );
      expect(
        service.debugIsRemoteNewer(
          localVersion: '2.4.1',
          localBuild: 2046,
          remoteVersion: '2.5',
          remoteBuild: 1,
        ),
        isTrue,
      );
      expect(
        service.debugIsRemoteNewer(
          localVersion: '2.4.1',
          localBuild: 2046,
          remoteVersion: '2.4.1',
          remoteBuild: 2046,
        ),
        isFalse,
      );
      expect(
        service.debugIsRemoteNewer(
          localVersion: '2.4.2',
          localBuild: 1,
          remoteVersion: '2.4.1-beta1',
          remoteBuild: 9999,
        ),
        isFalse,
      );
    });
  });

  group('AppUpdateInfo.apkUrls parsing', () {
    test('parses apkUrls from JSON downloads field', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'version': '2.0.0',
        'build': 10,
        'apkUrl': 'https://default.apk',
        'downloads': <String, dynamic>{
          'android-arm64': 'https://arm64.apk',
          'universal': 'https://universal.apk',
        },
        'notes': '',
        'publishedAt': '',
      };

      final AppUpdateInfo info = AppUpdateInfo.fromJson(json);

      expect(info.apkUrls['android-arm64'], 'https://arm64.apk');
      expect(info.apkUrls['universal'], 'https://universal.apk');
    });

    test('filters out empty apkUrls entries', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'version': '2.0.0',
        'build': 10,
        'apkUrl': '',
        'downloads': <String, dynamic>{
          'android-arm64': '',
          'universal': 'https://valid.apk',
        },
        'notes': '',
        'publishedAt': '',
      };

      final AppUpdateInfo info = AppUpdateInfo.fromJson(json);

      expect(info.apkUrls.containsKey('android-arm64'), false);
      expect(info.apkUrls['universal'], 'https://valid.apk');
    });
  });

  group('AppUpdateInfo.sha256Map parsing', () {
    test('parses sha256 from JSON', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'version': '2.0.0',
        'build': 10,
        'apkUrl': '',
        'sha256': <String, dynamic>{
          'android-arm64': 'abcdef1234567890',
          'universal': '0987654321fedcba',
        },
        'notes': '',
        'publishedAt': '',
      };

      final AppUpdateInfo info = AppUpdateInfo.fromJson(json);

      expect(info.sha256Map['android-arm64'], 'abcdef1234567890');
      expect(info.sha256Map['universal'], '0987654321fedcba');
    });

    test('sha256Map is empty when not provided', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'version': '1.0',
        'apkUrl': '',
      };

      final AppUpdateInfo info = AppUpdateInfo.fromJson(json);

      expect(info.sha256Map, isEmpty);
    });
  });
}
