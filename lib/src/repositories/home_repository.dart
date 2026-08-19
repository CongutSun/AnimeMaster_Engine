import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/bangumi_api.dart';
import '../models/anime.dart';

typedef HomeCalendarLoader = Future<List<dynamic>> Function();
typedef HomeTopLoader = Future<List<Map<String, dynamic>>> Function();

class HomeDataUnavailableException implements Exception {
  const HomeDataUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'HomeDataUnavailableException: $message';
}

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
  HomeRepository({HomeCalendarLoader? calendarLoader, HomeTopLoader? topLoader})
    : _calendarLoader = calendarLoader ?? BangumiApi.instance.getCalendar,
      _topLoader = topLoader ?? BangumiApi.instance.getYearTop;

  static const Duration _cacheTtl = Duration(hours: 4);
  static const Duration _staleCalendarTtl = Duration(days: 1);
  static const Duration _staleTopTtl = Duration(days: 7);
  static const String _calendarCacheKey = 'cache_calendar';
  static const String _topCacheKey = 'cache_top';
  static const String _legacyCacheTimeKey = 'cache_time';
  static const String _calendarCacheTimeKey = 'cache_calendar_time';
  static const String _topCacheTimeKey = 'cache_top_time';

  final HomeCalendarLoader _calendarLoader;
  final HomeTopLoader _topLoader;

  Future<HomeContentSnapshot?> loadCachedSnapshot({
    required bool forceRefresh,
  }) async {
    if (forceRefresh) {
      return null;
    }

    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (error) {
      debugPrint('[HomeRepository] Cache unavailable: $error');
      return null;
    }

    final String? calendarJson = _readCachedListJson(
      prefs,
      dataKey: _calendarCacheKey,
      timeKey: _calendarCacheTimeKey,
      maxAge: _cacheTtl,
    );
    if (calendarJson == null) {
      return null;
    }
    final String topJson =
        _readCachedListJson(
          prefs,
          dataKey: _topCacheKey,
          timeKey: _topCacheTimeKey,
          maxAge: _cacheTtl,
        ) ??
        '[]';

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
    final List<Object> results = await Future.wait<Object>(<Future<Object>>[
      _loadCalendarSafely(),
      _loadTopSafely(),
    ]);
    final List<dynamic> networkCalendar = results[0] as List<dynamic>;
    final List<Map<String, dynamic>> networkTop =
        results[1] as List<Map<String, dynamic>>;

    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (error) {
      debugPrint('[HomeRepository] Cache unavailable: $error');
    }

    final bool hasNetworkCalendar = _isUsableCalendar(networkCalendar);
    final String? calendarJson = hasNetworkCalendar
        ? jsonEncode(networkCalendar)
        : prefs == null
        ? null
        : _readCachedListJson(
            prefs,
            dataKey: _calendarCacheKey,
            timeKey: _calendarCacheTimeKey,
            maxAge: _staleCalendarTtl,
          );
    if (calendarJson == null) {
      throw const HomeDataUnavailableException(
        'Bangumi calendar data is unavailable and no usable cache exists.',
      );
    }

    final bool hasNetworkTop = networkTop.isNotEmpty;
    final String topJson = hasNetworkTop
        ? jsonEncode(networkTop)
        : prefs == null
        ? '[]'
        : _readCachedListJson(
                prefs,
                dataKey: _topCacheKey,
                timeKey: _topCacheTimeKey,
                maxAge: _staleTopTtl,
              ) ??
              '[]';

    if (prefs != null) {
      await _persistNetworkSections(
        prefs,
        calendarJson: hasNetworkCalendar ? calendarJson : null,
        topJson: hasNetworkTop ? topJson : null,
      );
    }

    return compute(_parseHomeSnapshot, <String, String>{
      'calendar': calendarJson,
      'top': topJson,
    });
  }

  Future<List<dynamic>> _loadCalendarSafely() async {
    try {
      return await _calendarLoader();
    } catch (error) {
      debugPrint('[HomeRepository] Calendar request failed: $error');
      return <dynamic>[];
    }
  }

  Future<List<Map<String, dynamic>>> _loadTopSafely() async {
    try {
      return await _topLoader();
    } catch (error) {
      debugPrint('[HomeRepository] Ranking request failed: $error');
      return <Map<String, dynamic>>[];
    }
  }

  bool _isUsableCalendar(List<dynamic> calendar) {
    return calendar.any((dynamic day) => day is Map && day['items'] is List);
  }

  String? _readCachedListJson(
    SharedPreferences prefs, {
    required String dataKey,
    required String timeKey,
    required Duration maxAge,
  }) {
    try {
      final String? value = prefs.getString(dataKey);
      final String? timeText =
          prefs.getString(timeKey) ?? prefs.getString(_legacyCacheTimeKey);
      final DateTime? cachedAt = timeText == null
          ? null
          : DateTime.tryParse(timeText);
      if (value == null || cachedAt == null) {
        return null;
      }

      final Duration age = DateTime.now().difference(cachedAt);
      if (age >= maxAge) {
        return null;
      }

      final Object? decoded = jsonDecode(value);
      return decoded is List && decoded.isNotEmpty ? value : null;
    } catch (error) {
      debugPrint('[HomeRepository] Ignoring invalid cache $dataKey: $error');
      return null;
    }
  }

  Future<void> _persistNetworkSections(
    SharedPreferences prefs, {
    required String? calendarJson,
    required String? topJson,
  }) async {
    if (calendarJson == null && topJson == null) {
      return;
    }

    try {
      final String now = DateTime.now().toIso8601String();
      final List<Future<bool>> writes = <Future<bool>>[];
      if (calendarJson != null) {
        writes.add(prefs.setString(_calendarCacheKey, calendarJson));
        writes.add(prefs.setString(_calendarCacheTimeKey, now));
      }
      if (topJson != null) {
        writes.add(prefs.setString(_topCacheKey, topJson));
        writes.add(prefs.setString(_topCacheTimeKey, now));
      }
      if (calendarJson != null && topJson != null) {
        writes.add(prefs.setString(_legacyCacheTimeKey, now));
      }
      await Future.wait<bool>(writes);
    } catch (error) {
      // Cache persistence is an optimization and must never break the page.
      debugPrint('[HomeRepository] Cache persistence failed: $error');
    }
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
