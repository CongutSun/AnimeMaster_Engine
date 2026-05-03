import 'dart:io' show File;
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../repositories/home_repository.dart';
import '../viewmodels/home_view_model.dart';
import '../widgets/anime_grid.dart';
import '../widgets/skeleton.dart';
import '../widgets/top_tool_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final HomeViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = HomeViewModel();
    _viewModel.load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Widget _buildWeekSchedule(HomeContentSnapshot snapshot) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: snapshot.weekSchedule
          .map((HomeScheduleDay day) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.live_tv_rounded,
                        color: colors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        day.weekdayName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AnimeGrid(animeList: day.animeList, isTop: false),
                ],
              ),
            );
          })
          .toList(growable: false),
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

  Widget _buildContent(HomeViewState state) {
    final HomeContentSnapshot? snapshot = state.snapshot;
    if (state.isLoading && snapshot == null) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SkeletonBlock(width: 180, height: 32),
                SizedBox(height: 16),
                AnimeGridSkeleton(itemCount: 6),
                SizedBox(height: 32),
                SkeletonBlock(width: 160, height: 32),
                SizedBox(height: 16),
                AnimeGridSkeleton(itemCount: 6),
              ],
            ),
          ),
        ),
      );
    }
    if (state.errorMessage != null && snapshot == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              state.errorMessage!,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _viewModel.load(forceRefresh: true),
              child: const Text('重新加载'),
            ),
          ],
        ),
      );
    }
    if (snapshot == null) {
      return const SizedBox.shrink();
    }

    return RefreshIndicator(
      onRefresh: () => _viewModel.load(forceRefresh: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildSectionHeader(
                  icon: Icons.calendar_month_rounded,
                  title: state.showTodayOnly
                      ? '${snapshot.todayString} · 今日排期'
                      : '本周整体排期',
                  trailing: TextButton.icon(
                    onPressed: _viewModel.toggleScheduleMode,
                    icon: Icon(
                      state.showTodayOnly
                          ? Icons.calendar_view_week_rounded
                          : Icons.today_rounded,
                      size: 18,
                    ),
                    label: Text(state.showTodayOnly ? '查看全周' : '查看今日'),
                  ),
                ),
                const SizedBox(height: 16),
                state.showTodayOnly
                    ? AnimeGrid(animeList: snapshot.todayAnime, isTop: false)
                    : _buildWeekSchedule(snapshot),
                const SizedBox(height: 32),
                _buildSectionHeader(
                  icon: Icons.emoji_events_rounded,
                  title: '本年度高分榜单',
                  iconColor: const Color(0xFFFF9F0A),
                ),
                const SizedBox(height: 16),
                AnimeGrid(animeList: snapshot.topAnime, isTop: true),
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
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: ColoredBox(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.46)
                        : colors.surface.withValues(alpha: 0.24),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: <Widget>[
                const TopToolBar(),
                Expanded(
                  child: AnimatedBuilder(
                    animation: _viewModel,
                    builder: (BuildContext context, Widget? child) {
                      return _buildContent(_viewModel.state);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
