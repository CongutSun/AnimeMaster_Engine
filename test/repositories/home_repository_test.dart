import 'dart:convert';

import 'package:animemaster/src/repositories/home_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<dynamic> _calendarData({int subjectId = 1}) {
  return <dynamic>[
    <String, dynamic>{
      'weekday': <String, dynamic>{'id': DateTime.now().weekday, 'cn': '今天'},
      'items': <dynamic>[
        <String, dynamic>{'id': subjectId, 'name': '排期动画'},
      ],
    },
  ];
}

List<Map<String, dynamic>> _topData({int subjectId = 2}) {
  return <Map<String, dynamic>>[
    <String, dynamic>{
      'id': subjectId,
      'name': '榜单动画',
      'rating': <String, dynamic>{'score': '9.0'},
    },
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('HomeRepository resilience', () {
    test('keeps the homepage usable when ranking fails', () async {
      final HomeRepository repository = HomeRepository(
        calendarLoader: () async => _calendarData(),
        topLoader: () async => throw StateError('ranking unavailable'),
      );

      final HomeContentSnapshot snapshot = await repository
          .fetchNetworkSnapshot();

      expect(snapshot.todayAnime, hasLength(1));
      expect(snapshot.topAnime, isEmpty);
      expect(snapshot.weekSchedule, hasLength(1));
    });

    test(
      'uses a recent stale calendar when the network request fails',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'cache_calendar': jsonEncode(_calendarData(subjectId: 10)),
          'cache_calendar_time': DateTime.now()
              .subtract(const Duration(hours: 8))
              .toIso8601String(),
        });
        final HomeRepository repository = HomeRepository(
          calendarLoader: () async => throw StateError('calendar unavailable'),
          topLoader: () async => <Map<String, dynamic>>[],
        );

        final HomeContentSnapshot snapshot = await repository
            .fetchNetworkSnapshot();

        expect(snapshot.todayAnime.single.id, 10);
      },
    );

    test(
      'does not use calendar cache beyond the stale safety window',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'cache_calendar': jsonEncode(_calendarData()),
          'cache_calendar_time': DateTime.now()
              .subtract(const Duration(days: 2))
              .toIso8601String(),
        });
        final HomeRepository repository = HomeRepository(
          calendarLoader: () async => <dynamic>[],
          topLoader: () async => <Map<String, dynamic>>[],
        );

        expect(
          repository.fetchNetworkSnapshot(),
          throwsA(isA<HomeDataUnavailableException>()),
        );
      },
    );

    test(
      'loads a fresh calendar cache even when ranking cache is absent',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'cache_calendar': jsonEncode(_calendarData()),
          'cache_calendar_time': DateTime.now().toIso8601String(),
        });
        final HomeRepository repository = HomeRepository(
          calendarLoader: () async => <dynamic>[],
          topLoader: () async => <Map<String, dynamic>>[],
        );

        final HomeContentSnapshot? snapshot = await repository
            .loadCachedSnapshot(forceRefresh: false);

        expect(snapshot, isNotNull);
        expect(snapshot!.todayAnime, hasLength(1));
        expect(snapshot.topAnime, isEmpty);
      },
    );

    test(
      'uses stale ranking without overwriting its original timestamp',
      () async {
        final String topCachedAt = DateTime.now()
            .subtract(const Duration(days: 2))
            .toIso8601String();
        SharedPreferences.setMockInitialValues(<String, Object>{
          'cache_top': jsonEncode(_topData(subjectId: 20)),
          'cache_top_time': topCachedAt,
        });
        final HomeRepository repository = HomeRepository(
          calendarLoader: () async => _calendarData(),
          topLoader: () async => <Map<String, dynamic>>[],
        );

        final HomeContentSnapshot snapshot = await repository
            .fetchNetworkSnapshot();
        final SharedPreferences prefs = await SharedPreferences.getInstance();

        expect(snapshot.topAnime.single.id, 20);
        expect(prefs.getString('cache_top_time'), topCachedAt);
        expect(prefs.getString('cache_calendar_time'), isNotNull);
      },
    );

    test('ignores cache values stored with an invalid type', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'cache_calendar': true,
        'cache_calendar_time': DateTime.now().toIso8601String(),
      });
      final HomeRepository repository = HomeRepository(
        calendarLoader: () async => <dynamic>[],
        topLoader: () async => <Map<String, dynamic>>[],
      );

      final HomeContentSnapshot? snapshot = await repository.loadCachedSnapshot(
        forceRefresh: false,
      );

      expect(snapshot, isNull);
    });
  });
}
