import 'package:animemaster/src/services/online_episode_source_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('first source lookup includes the bundled adaptive registry', () async {
    final int count =
        await OnlineEpisodeSourceService.debugConfiguredSourceCount();

    expect(count, greaterThan(6));
  });
}
