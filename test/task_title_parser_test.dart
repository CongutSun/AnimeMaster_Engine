import 'package:flutter_test/flutter_test.dart';
import 'package:animemaster/src/utils/task_title_parser.dart';

void main() {
  test('extracts SxxExx episode numbers', () {
    expect(TaskTitleParser.extractEpisodeNumber('[Group] Title S02E13'), 13);
    expect(
      TaskTitleParser.extractEpisodeLabel('[Group] Title S02E13'),
      'S02E13',
    );
  });

  test('extracts Chinese episode labels', () {
    expect(TaskTitleParser.extractEpisodeNumber('番剧 第 12 集 终章'), 12);
    expect(TaskTitleParser.extractEpisodeLabel('番剧 第 12 集 终章'), '第 12 集');
  });

  test('builds stable display labels', () {
    expect(
      TaskTitleParser.buildEpisodeDisplayLabel(
        episodeNumber: 7,
        episodeTitle: 'Restart',
      ),
      '第 7 集 · Restart',
    );
  });

  group('matchesEpisodeNumber', () {
    test('matches common single episode release formats', () {
      expect(
        TaskTitleParser.matchesEpisodeNumber(
          '[Lilith-Raws] Example - 03 [Baha][1080p]',
          3,
        ),
        isTrue,
      );
      expect(
        TaskTitleParser.matchesEpisodeNumber('[Group] Example S02E13v2', 13),
        isTrue,
      );
      expect(TaskTitleParser.matchesEpisodeNumber('Example 第 7 话', 7), isTrue);
      expect(
        TaskTitleParser.matchesEpisodeNumber('Example [09][HEVC]', 9),
        isTrue,
      );
      expect(
        TaskTitleParser.matchesEpisodeNumber('Example 11 (B-Global 1080p)', 11),
        isTrue,
      );
    });

    test('does not confuse metadata or batch ranges with a single episode', () {
      expect(
        TaskTitleParser.matchesEpisodeNumber(
          '[Group] Example [1080p][10bit][2026]',
          10,
        ),
        isFalse,
      );
      expect(
        TaskTitleParser.matchesEpisodeNumber('Example 01-12 [1080p]', 12),
        isFalse,
      );
      expect(
        TaskTitleParser.matchesEpisodeNumber('Example - 04 [1080p]', 3),
        isFalse,
      );
    });
  });
}
