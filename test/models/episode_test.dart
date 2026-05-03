import 'package:flutter_test/flutter_test.dart';
import 'package:animemaster/src/models/episode.dart';

void main() {
  group('Episode.fromJson', () {
    test('parses complete Bangumi episode JSON', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'id': 12345,
        'ep': 7,
        'sort': 7,
        'name': 'Restart',
        'name_cn': '重启',
        'airdate': '2025-01-15',
        'desc': 'The hero returns.',
        'duration': '24:00',
      };

      final Episode episode = Episode.fromJson(json, subjectId: 42);

      expect(episode.id, 12345);
      expect(episode.subjectId, 42);
      expect(episode.episodeNumber, 7);
      expect(episode.sort, 7);
      expect(episode.title, 'Restart');
      expect(episode.titleCn, '重启');
      expect(episode.airdate, '2025-01-15');
      expect(episode.description, 'The hero returns.');
      expect(episode.duration, '24:00');
    });

    test('falls back to sort when ep is missing', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'id': 100,
        'sort': 3,
        'name': 'Title',
        'name_cn': '',
      };

      final Episode episode = Episode.fromJson(json);

      expect(episode.episodeNumber, 3);
    });

    test('handles missing optional fields gracefully', () {
      final Map<String, dynamic> json = <String, dynamic>{'id': 1};

      final Episode episode = Episode.fromJson(json);

      expect(episode.id, 1);
      expect(episode.episodeNumber, 0);
      expect(episode.title, '');
      expect(episode.titleCn, '');
      expect(episode.description, '');
    });

    test('handles string numeric values', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'id': '200',
        'ep': '5',
        'sort': '5',
      };

      final Episode episode = Episode.fromJson(json);

      expect(episode.id, 200);
      expect(episode.episodeNumber, 5);
    });

    test('trims whitespace from string fields', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'id': 1,
        'name': '  Hello World  ',
        'name_cn': '  你好  ',
      };

      final Episode episode = Episode.fromJson(json);

      expect(episode.title, 'Hello World');
      expect(episode.titleCn, '你好');
    });
  });

  group('Episode.toJson', () {
    test('round-trips correctly', () {
      final Episode episode = Episode(
        id: 42,
        subjectId: 7,
        episodeNumber: 3,
        sort: 3,
        title: 'Test',
      );

      final Map<String, dynamic> json = episode.toJson();

      expect(json['id'], 42);
      expect(json['subject_id'], 7);
      expect(json['ep'], 3);
      expect(json['name'], 'Test');
    });
  });

  group('Episode display helpers', () {
    test('displayNumber returns string for positive', () {
      expect(const Episode(id: 1, episodeNumber: 5).displayNumber, '5');
    });

    test('displayNumber returns ? for zero', () {
      expect(const Episode(id: 1, episodeNumber: 0).displayNumber, '?');
    });

    test('chartKey uses episode number when positive', () {
      expect(const Episode(id: 1, episodeNumber: 3).chartKey, '3');
    });

    test('chartKey falls back to id when no episode number', () {
      expect(const Episode(id: 42, episodeNumber: 0).chartKey, '42');
    });
  });
}
