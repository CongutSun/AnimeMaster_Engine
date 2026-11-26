import 'package:animemaster/src/models/anime.dart';
import 'package:animemaster/src/theme/app_theme.dart';
import 'package:animemaster/src/widgets/anime_grid.dart';
import 'package:animemaster/src/providers/settings_provider.dart';
import 'package:animemaster/src/screens/settings_page.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('小屏大字可以从设置首页选择外观并看到已保存的状态', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final prefs = SettingsProvider();
    await prefs.initialize();
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: prefs,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('外观与操作'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('海盐青'));
    await tester.tap(find.text('海盐青'));
    await tester.pumpAndSettle();
    expect(prefs.palette, 'sea');
    await tester.ensureVisible(find.text('系统字体'));
    await tester.tap(find.text('系统字体'));
    await tester.pumpAndSettle();
    expect(prefs.serifTitles, isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('海盐青 · 跟随系统'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('八种明暗配色的文字和按钮达到 4.5:1', () {
    double contrast(Color a, Color b) {
      final values = [a.computeLuminance(), b.computeLuminance()]..sort();
      return (values.last + .05) / (values.first + .05);
    }

    for (final palette in AppPalette.values) {
      for (final theme in [
        AppTheme.light(palette: palette),
        AppTheme.dark(palette: palette),
      ]) {
        final scheme = theme.colorScheme;
        expect(
          contrast(scheme.primary, scheme.onPrimary),
          greaterThanOrEqualTo(4.5),
        );
        for (final background in [
          theme.scaffoldBackgroundColor,
          scheme.surface,
        ]) {
          for (final color in [
            scheme.primary,
            scheme.onSurface,
            scheme.onSurfaceVariant,
            scheme.error,
          ]) {
            expect(
              contrast(background, color),
              greaterThanOrEqualTo(4.5),
              reason: palette.name,
            );
          }
        }
      }
    }
  });
  for (final width in [320.0, 360.0, 412.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('长片名海报适应宽度 $width 和字号 $scale', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final anime = Anime(
          id: 1,
          name: '夏への扉 The Door into Summer',
          nameCn: '通往夏天的门与另一个世界的很长的名字',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: AnimeGrid(animeList: [anime, anime, anime]),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final grid = tester.widget<GridView>(find.byType(GridView));
        final columns =
            (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
                .crossAxisCount;
        if (width == 320 && scale == 1) expect(columns, 2);
        if (scale == 2) expect(columns, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
