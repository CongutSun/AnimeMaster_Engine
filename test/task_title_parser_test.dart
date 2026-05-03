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
}
