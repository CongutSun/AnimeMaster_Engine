import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/bangumi_api.dart';
import '../models/anime.dart';

class HomeScheduleDay {
  final String weekdayName;
  final List<Anime> animeList;

  const HomeScheduleDay({required this.weekdayName, required this.animeList});
}

class HomeContentSnapshot {
  final String todayString;
  final List<Anime> todayAnime;
  final List<Anime> topAnime;
  final List<HomeScheduleDay> weekSchedule;

  const HomeContentSnapshot({
    required this.todayString,
    required this.todayAnime,
    required this.topAnime,
    required this.weekSchedule,
  });
}

class HomeRepository {
  static const Duration _cacheTtl = Duration(hours: 4);
  static const String _calendarCacheKey = 'cache_calendar';
  static const String _topCacheKey = 'cache_top';
  static const String _cacheTimeKey = 'cache_time';

  Future<HomeContentSnapshot?> loadCachedSnapshot({
    required bool forceRefresh,
  }) async {
    if (forceRefresh) {
      return null;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? calendarJson = prefs.getString(_calendarCacheKey);
    final String? topJson = prefs.getString(_topCacheKey);
    final String? cacheTimeText = prefs.getString(_cacheTimeKey);
    if (calendarJson == null || topJson == null || cacheTimeText == null) {
      return null;
    }

    final DateTime? cacheTime = DateTime.tryParse(cacheTimeText);
    if (cacheTime == null ||
        DateTime.now().difference(cacheTime) >= _cacheTtl) {
      return null;
    }

    try {
      return compute(_parseHomeSnapshot, <String, String>{
        'calendar': calendarJson,
        'top': topJson,
      });
    } catch (error) {
      debugPrint('[HomeRepository] Cache parsing failed: $error');
      return null;
    }
  }

  Future<HomeContentSnapshot> fetchNetworkSnapshot() async {
    final List<List<dynamic>> results =
        await Future.wait<List<dynamic>>(<Future<List<dynamic>>>[
          BangumiApi.instance.getCalendar(),
          BangumiApi.instance.getYearTop().then(
            (List<Map<String, dynamic>> value) => List<dynamic>.from(value),
          ),
        ]);

    final List<dynamic> calendar = results[0];
    final List<Map<String, dynamic>> rawTopData = results[1]
        .whereType<Map>()
        .map((Map<dynamic, dynamic> item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

    if (calendar.isEmpty || rawTopData.isEmpty) {
      throw StateError('Bangumi returned empty home data.');
    }

    final String calendarJson = jsonEncode(calendar);
    final String topJson = jsonEncode(rawTopData);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_calendarCacheKey, calendarJson);
    await prefs.setString(_topCacheKey, topJson);
    await prefs.setString(_cacheTimeKey, DateTime.now().toIso8601String());

    return compute(_parseHomeSnapshot, <String, String>{
      'calendar': calendarJson,
      'top': topJson,
    });
  }
}

HomeContentSnapshot _parseHomeSnapshot(Map<String, String> payload) {
  final Object? calendarDecoded = jsonDecode(payload['calendar'] ?? '[]');
  final Object? topDecoded = jsonDecode(payload['top'] ?? '[]');
  final List<dynamic> calendar = calendarDecoded is List
      ? calendarDecoded
      : <dynamic>[];
  final List<Map<String, dynamic>> rawTopData = topDecoded is List
      ? topDecoded
            .whereType<Map>()
            .map(
              (Map<dynamic, dynamic> item) => Map<String, dynamic>.from(item),
            )
            .toList(growable: false)
      : <Map<String, dynamic>>[];

  final int weekday = DateTime.now().weekday;
  const List<String> days = <String>[
    '星期一',
    '星期二',
    '星期三',
    '星期四',
    '星期五',
    '星期六',
    '星期日',
  ];

  List<Anime> todayAnime = <Anime>[];
  final List<HomeScheduleDay> weekSchedule = <HomeScheduleDay>[];

  for (final dynamic rawDay in calendar) {
    if (rawDay is! Map) {
      continue;
    }
    final Map<String, dynamic> day = Map<String, dynamic>.from(rawDay);
    final Object? rawWeekday = day['weekday'];
    final Map<String, dynamic> weekdayMap = rawWeekday is Map
        ? Map<String, dynamic>.from(rawWeekday)
        : <String, dynamic>{};
    final int fallbackDayId = weekSchedule.length + 1;
    final int dayId =
        int.tryParse(weekdayMap['id']?.toString() ?? '') ?? fallbackDayId;
    final String weekdayName =
        weekdayMap['cn']?.toString() ??
        weekdayMap['en']?.toString() ??
        (dayId >= 1 && dayId <= days.length ? days[dayId - 1] : '未知');
    final List<dynamic> rawItems = day['items'] is List
        ? day['items'] as List<dynamic>
        : <dynamic>[];
    final List<Anime> animeList = rawItems
        .whereType<Map>()
        .map(
          (Map<dynamic, dynamic> item) =>
              Anime.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);

    if (dayId == weekday) {
      todayAnime = animeList;
    }
    weekSchedule.add(
      HomeScheduleDay(weekdayName: weekdayName, animeList: animeList),
    );
  }

  return HomeContentSnapshot(
    todayString: days[weekday - 1],
    todayAnime: todayAnime,
    topAnime: rawTopData.map(Anime.fromJson).toList(growable: false),
    weekSchedule: weekSchedule,
  );
}
