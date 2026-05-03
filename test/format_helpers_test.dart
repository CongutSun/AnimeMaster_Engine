import 'package:flutter_test/flutter_test.dart';
import 'package:animemaster/src/utils/format_helpers.dart';

void main() {
  group('formatDuration', () {
    test('seconds only', () {
      expect(formatDuration(const Duration(seconds: 45)), '0:45');
    });
    test('minutes and seconds', () {
      expect(formatDuration(const Duration(minutes: 3, seconds: 7)), '3:07');
    });
    test('hours', () {
      expect(
        formatDuration(const Duration(hours: 1, minutes: 22, seconds: 15)),
        '1:22:15',
      );
    });
    test('zero', () {
      expect(formatDuration(Duration.zero), '0:00');
    });
  });

  group('formatLocalDateTime', () {
    test('returns expected format', () {
      final DateTime dt = DateTime(2026, 5, 3, 14, 30);
      final String result = formatLocalDateTime(dt);
      expect(result, contains('2026-05-03'));
      expect(result, contains('14:30'));
    });
  });
}
