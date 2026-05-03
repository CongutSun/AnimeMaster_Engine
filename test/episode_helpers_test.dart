import 'package:flutter_test/flutter_test.dart';
import 'package:animemaster/src/utils/episode_helpers.dart';

void main() {
  group('episodeNumber', () {
    test('returns int ep value', () {
      expect(episodeNumber(<String, dynamic>{'ep': 42}), 42);
    });

    test('falls back to sort when ep is missing', () {
      expect(episodeNumber(<String, dynamic>{'sort': 7}), 7);
    });

    test('returns 0 for missing keys', () {
      expect(episodeNumber(<String, dynamic>{}), 0);
    });

    test('handles string values', () {
      expect(episodeNumber(<String, dynamic>{'ep': '99'}), 99);
    });
  });

  group('stripRedundantEpisodePrefix', () {
    test('removes 第N集 prefix', () {
      expect(
        stripRedundantEpisodePrefix('第1集 プロローグ', 1),
        'プロローグ',
      );
    });

    test('removes numbered prefix', () {
      expect(
        stripRedundantEpisodePrefix('01 始まり', 1),
        '始まり',
      );
    });

    test('returns title unchanged when no prefix', () {
      expect(
        stripRedundantEpisodePrefix('オリジナルタイトル', 5),
        'オリジナルタイトル',
      );
    });
  });

  group('episodeTitle', () {
    test('builds display title from name_cn', () {
      expect(
        episodeTitle(<String, dynamic>{
          'ep': 3,
          'name_cn': '第3集 旅立ち',
        }),
        '旅立ち',
      );
    });

    test('falls back to numbered label for empty title', () {
      expect(
        episodeTitle(<String, dynamic>{'ep': 5}),
        '第5集',
      );
    });
  });

  group('safeInt', () {
    test('int passthrough', () => expect(safeInt(10), 10));
    test('num rounding', () => expect(safeInt(3.7), 4));
    test('String parsing', () => expect(safeInt('88'), 88));
    test('invalid returns 0', () => expect(safeInt('abc'), 0));
    test('null returns 0', () => expect(safeInt(null), 0));
  });

  group('extractEpisodeNumber', () {
    test('S01E03', () {
      expect(extractEpisodeNumber('S01E03'), 3);
    });
    test('EP05', () {
      expect(extractEpisodeNumber('EP05'), 5);
    });
    test('第7話', () {
      expect(extractEpisodeNumber('第7話'), 7);
    });
    test('isolated number', () {
      expect(extractEpisodeNumber('12'), 12);
    });
    test('no number returns null', () {
      expect(extractEpisodeNumber('no digits'), isNull);
    });
  });
}
