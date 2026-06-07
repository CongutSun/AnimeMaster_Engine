import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:animemaster/src/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'read') {
              return null;
            }
            return null;
          },
        );
  });

  group('SettingsProvider appearance', () {
    test('default theme mode is Light', () async {
      final SettingsProvider provider = SettingsProvider();
      await provider.initialize();
      expect(provider.themeMode, 'Light');
    });

    test('default close action is minimize', () async {
      final SettingsProvider provider = SettingsProvider();
      await provider.initialize();
      expect(provider.closeAction, 'minimize');
    });
  });

  group('SettingsProvider playback options', () {
    test('default resume behavior is ask', () async {
      final SettingsProvider provider = SettingsProvider();
      await provider.initialize();
      expect(provider.resumePlaybackBehavior, 'ask');
    });

    test('default picture-in-picture is disabled', () async {
      final SettingsProvider provider = SettingsProvider();
      await provider.initialize();
      expect(provider.enablePictureInPicture, false);
    });

    test('updatePlaybackOptions triggers notifyListeners', () async {
      final SettingsProvider provider = SettingsProvider();
      await provider.initialize();

      bool didNotify = false;
      provider.addListener(() => didNotify = true);

      await provider.updatePlaybackOptions(
        enablePictureInPicture: true,
        resumePlaybackBehavior: 'auto',
        autoPlayNextEpisode: true,
      );

      expect(didNotify, true);
      expect(provider.enablePictureInPicture, true);
      expect(provider.resumePlaybackBehavior, 'auto');
      expect(provider.autoPlayNextEpisode, true);
    });

    test('updatePlaybackOptions normalizes invalid resume behavior', () async {
      final SettingsProvider provider = SettingsProvider();
      await provider.initialize();

      await provider.updatePlaybackOptions(
        enablePictureInPicture: false,
        resumePlaybackBehavior: 'invalid_value',
      );

      expect(provider.resumePlaybackBehavior, 'ask');
    });
  });

  group('SettingsProvider RSS sources', () {
    test('RSS sources start with bundled defaults', () async {
      final SettingsProvider provider = SettingsProvider();
      await provider.initialize();
      expect(provider.rssSources, isNotEmpty);
    });

    test('addRssSource adds entry', () async {
      final SettingsProvider provider = SettingsProvider();
      await provider.initialize();

      bool didNotify = false;
      provider.addListener(() => didNotify = true);

      await provider.addRssSource('Mikan', 'https://mikanani.me');

      expect(didNotify, true);
      expect(provider.rssSources.length, 3);
      expect(provider.rssSources.last['name'], 'Mikan');
    });

    test('removeRssSource removes entry at valid index', () async {
      final SettingsProvider provider = SettingsProvider();
      await provider.initialize();
      await provider.addRssSource('A', 'https://a.com');
      await provider.addRssSource('B', 'https://b.com');

      await provider.removeRssSource(2);

      expect(provider.rssSources.length, 3);
      expect(
        provider.rssSources.any(
          (Map<String, String> source) => source['name'] == 'A',
        ),
        false,
      );
    });

    test('removeRssSource ignores invalid index', () async {
      final SettingsProvider provider = SettingsProvider();
      await provider.initialize();
      await provider.addRssSource('A', 'https://a.com');

      await provider.removeRssSource(99);

      expect(provider.rssSources.length, 3);
    });
  });

  group('SettingsProvider Bangumi auth', () {
    test('has no auth by default', () async {
      final SettingsProvider provider = SettingsProvider();
      await provider.initialize();

      expect(provider.hasBangumiToken, false);
      expect(provider.bgmAcc, '');
      expect(provider.bgmToken, '');
    });

    test('clearBangumiAuthorization resets state', () async {
      final SettingsProvider provider = SettingsProvider();
      await provider.initialize();

      await provider.clearBangumiAuthorization();

      expect(provider.hasBangumiToken, false);
      expect(provider.bgmAcc, '');
      expect(provider.bgmToken, '');
    });
  });

  group('SettingsProvider appearance changes', () {
    test('updateAppearance switches to dark mode', () async {
      final SettingsProvider provider = SettingsProvider();
      await provider.initialize();

      await provider.updateAppearance('minimize', 'dark', '');

      expect(provider.themeMode, 'Dark');
      expect(provider.closeAction, 'minimize');
    });

    test('updateAppearance normalizes invalid theme mode', () async {
      final SettingsProvider provider = SettingsProvider();
      await provider.initialize();

      await provider.updateAppearance('exit', 'invalid_mode', '');

      expect(provider.themeMode, 'Light');
    });
  });
}
