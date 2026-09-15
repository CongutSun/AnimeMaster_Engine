import 'package:animemaster/src/utils/transfer_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bounded batches eventually visit all trackers and wrap around', () {
    final TrackerRotation rotation = TrackerRotation();
    final List<Uri> trackers = List<Uri>.generate(
      23,
      (int i) => Uri.parse('udp://tracker$i.example:80/announce'),
    );
    final Set<Uri> visited = <Uri>{};
    for (int i = 0; i < 6; i++) {
      final List<Uri> batch = rotation.next(trackers, 4);
      expect(batch, hasLength(4));
      visited.addAll(batch);
    }
    expect(visited, trackers.toSet());
  });

  test(
    'rotation tolerates duplicate, invalid, empty and changed tracker lists',
    () {
      final TrackerRotation rotation = TrackerRotation();
      final Uri valid = Uri.parse('https://tracker.example/announce');
      expect(rotation.next([valid, valid, Uri.parse('file:///tmp/x')], 8), [
        valid,
      ]);
      expect(rotation.next([], 8), isEmpty);
      expect(rotation.next([valid], 0), isEmpty);
      expect(rotation.next([valid], 4), [valid]);
    },
  );

  test('new, productive and in-flight peers survive trimming', () {
    bool trim(Duration age, double speed, bool pending) =>
        TransferPolicy.canTrimPeer(
          age: age,
          downloadSpeed: speed,
          hasPendingRequests: pending,
          seeding: false,
        );
    expect(trim(const Duration(seconds: 30), 0, false), isFalse);
    expect(trim(const Duration(minutes: 3), 128, false), isFalse);
    expect(trim(const Duration(minutes: 3), 0, true), isFalse);
    expect(trim(const Duration(minutes: 3), 0, false), isTrue);
  });
}
