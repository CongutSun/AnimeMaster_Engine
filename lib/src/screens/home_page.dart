import 'dart:io' show File;
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/bangumi_api.dart';
import '../models/anime.dart';
import '../providers/settings_provider.dart';
import '../widgets/top_tool_bar.dart';
import '../widgets/anime_grid.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Anime> todayAnime = [];
  List<Anime> topAnime = [];
  List<dynamic> fullCalendar = [];

  bool isLoading = true;
  String? errorMessage;
  bool showTodayOnly = true;
  String todayString = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedCalendar = prefs.getString('cache_calendar');
    final cachedTop = prefs.getString('cache_top');
    final cacheTimeStr = prefs.getString('cache_time');

    bool hasValidCache = false;

    if (cachedCalendar != null &&
        cachedTop != null &&
        cacheTimeStr != null &&
        !forceRefresh) {
      try {
        final cacheTime = DateTime.parse(cacheTimeStr);
        if (DateTime.now().difference(cacheTime).inHours < 4) {
          final calendar = jsonDecode(cachedCalendar);
          final rawTopData = jsonDecode(cachedTop);

          if (calendar is List && rawTopData is List) {
            final validTopData = rawTopData
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            _parseAndSetData(calendar, validTopData);
            hasValidCache = true;
          }
        }
      } catch (e) {
        debugPrint('[HomePage] Cache parsing failed: $e');
      }
    }

    if (!hasValidCache) {
      if (mounted) {
        setState(() {
          isLoading = true;
          errorMessage = null;
        });
      }
      await _fetchNetworkData(prefs, isSilent: false);
    } else {
      _fetchNetworkData(prefs, isSilent: true);
    }
  }

  Future<void> _fetchNetworkData(
    SharedPreferences prefs, {
    bool isSilent = false,
  }) async {
    try {
      final results = await Future.wait([
        BangumiApi.getCalendar(),
        BangumiApi.getYearTop(),
      ]);

      // 修复 Linter: unnecessary_cast
      // Dart 自动推导出 results 的元素为 List，直接使用 List.from 转换内部元素即可
      final List<dynamic> calendar = results[0];
      final List<Map<String, dynamic>> rawTopData =
          List<Map<String, dynamic>>.from(results[1]);

      if (calendar.isNotEmpty && rawTopData.isNotEmpty) {
        await prefs.setString('cache_calendar', jsonEncode(calendar));
        await prefs.setString('cache_top', jsonEncode(rawTopData));
        await prefs.setString('cache_time', DateTime.now().toIso8601String());

        _parseAndSetData(calendar, rawTopData);
      } else if (!isSilent) {
        throw Exception("API returned empty data sequence.");
      }
    } catch (e) {
      debugPrint('[HomePage] Network fetch exception: $e');
      if (!isSilent && mounted && todayAnime.isEmpty) {
        setState(() {
          isLoading = false;
          errorMessage = '数据加载失败，请下拉重试或检查网络状态';
        });
      }
    }
  }

  void _parseAndSetData(
    List<dynamic> calendar,
    List<Map<String, dynamic>> rawTopData,
  ) {
    final weekday = DateTime.now().weekday;
    const days = ["星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"];
    todayString = days[weekday - 1];

    List<Anime> parsedToday = [];
    for (var day in calendar) {
      if (day is Map && day['weekday']?['id'] == weekday) {
        final items = day['items'] as List? ?? [];
        parsedToday = items
            .whereType<Map>()
            .map((e) => Anime.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        break;
      }
    }

    if (mounted) {
      setState(() {
        fullCalendar = calendar;
        todayAnime = parsedToday;
        topAnime = rawTopData.map((e) => Anime.fromJson(e)).toList();
        isLoading = false;
        errorMessage = null;
      });
    }
  }

  Widget _buildWeekSchedule() {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: fullCalendar.whereType<Map>().map((day) {
        final weekdayName =
            day['weekday']?['cn'] ?? day['weekday']?['en'] ?? '未知';
        final items = day['items'] as List? ?? [];
        final dayAnime = items
            .whereType<Map>()
            .map((e) => Anime.fromJson(Map<String, dynamic>.from(e)))
            .toList();

        return Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.live_tv_rounded, color: colors.primary, size: 18),
                  const SizedBox(width: 7),
                  Text(
                    weekdayName.toString(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AnimeGrid(animeList: dayAnime, isTop: false),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    Color? iconColor,
    Widget? trailing,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Color resolvedIconColor = iconColor ?? colors.primary;

    return Row(
      children: <Widget>[
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: resolvedIconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: resolvedIconColor, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _buildContent() {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(errorMessage!, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadData(forceRefresh: true),
              child: const Text('重新加载'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(forceRefresh: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader(
                  icon: Icons.calendar_month_rounded,
                  title: showTodayOnly ? '$todayString · 今日排期' : '本周整体排期',
                  trailing: TextButton.icon(
                    onPressed: () =>
                        setState(() => showTodayOnly = !showTodayOnly),
                    icon: Icon(
                      showTodayOnly
                          ? Icons.calendar_view_week_rounded
                          : Icons.today_rounded,
                      size: 18,
                    ),
                    label: Text(showTodayOnly ? '查看全周' : '查看今日'),
                  ),
                ),
                const SizedBox(height: 16),
                showTodayOnly
                    ? AnimeGrid(animeList: todayAnime, isTop: false)
                    : _buildWeekSchedule(),
                const SizedBox(height: 32),
                _buildSectionHeader(
                  icon: Icons.emoji_events_rounded,
                  title: '本年度高分榜单',
                  iconColor: const Color(0xFFFF9F0A),
                ),
                const SizedBox(height: 16),
                AnimeGrid(animeList: topAnime, isTop: true),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SettingsProvider settings = context.watch<SettingsProvider>();
    final String bgPath = settings.customBgPath;
    final bool hasBg =
        !kIsWeb && bgPath.isNotEmpty && File(bgPath).existsSync();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (hasBg)
            Positioned.fill(
              child: Image.file(
                File(bgPath),
                fit: BoxFit.cover,
                alignment: Alignment.bottomCenter,
              ),
            ),
          if (hasBg)
            Positioned.fill(
              child: ColoredBox(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.46)
                    : colors.surface.withValues(alpha: 0.24),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                const TopToolBar(),
                Expanded(child: _buildContent()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
