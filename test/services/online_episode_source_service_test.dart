import 'package:animemaster/src/services/online_episode_source_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  OnlineEpisodeSourceService.debugDisableRemoteRefresh();

  test('first source lookup includes the bundled adaptive registry', () async {
    final int count =
        await OnlineEpisodeSourceService.debugConfiguredSourceCount();

    expect(count, greaterThan(6));
  });

  group('remote source trust boundary', () {
    test('accepts public HTTPS sources', () {
      expect(
        OnlineEpisodeSourceService.debugIsTrustedRemoteSourceUrl(
          'https://media.example.com/api.php/provide/vod/',
        ),
        isTrue,
      );
      expect(
        OnlineEpisodeSourceService.debugIsTrustedRemoteSourceUrl(
          'https://1.1.1.1/source',
        ),
        isTrue,
      );
    });

    test('rejects non-HTTPS and local network sources', () {
      for (final String url in <String>[
        'http://media.example.com',
        'https://localhost/source',
        'https://127.0.0.1/source',
        'https://127.1/source',
        'https://0.0.0.0/source',
        'https://10.0.0.8/source',
        'https://169.254.1.1/source',
        'https://172.20.1.1/source',
        'https://192.168.1.8/source',
        'https://224.0.0.1/source',
        'https://999.1.1.1/source',
        'https://[::1]/source',
        'https://[fd00::1]/source',
      ]) {
        expect(
          OnlineEpisodeSourceService.debugIsTrustedRemoteSourceUrl(url),
          isFalse,
          reason: url,
        );
      }
    });
  });
}
