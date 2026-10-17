import 'dart:io';
import 'dart:ui' as ui;

import 'package:animemaster/src/models/bilibili_video.dart';
import 'package:animemaster/src/models/online_episode_source.dart';
import 'package:animemaster/src/models/rss_resource.dart';
import 'package:animemaster/src/providers/settings_provider.dart';
import 'package:animemaster/src/repositories/bilibili_episode_mapping_repository.dart';
import 'package:animemaster/src/screens/bilibili_video_details_page.dart';
import 'package:animemaster/src/screens/magnet_config_page.dart';
import 'package:animemaster/src/screens/resource_search_page.dart';
import 'package:animemaster/src/services/bilibili_auth_service.dart';
import 'package:animemaster/src/services/bilibili_video_service.dart';
import 'package:animemaster/src/services/rss_feed_service.dart';
import 'package:animemaster/src/storage/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends BilibiliAuthService {
  @override
  Future<void> initialize() async {}
}

class _Videos extends BilibiliVideoService {
  final List<String> keywords = <String>[];

  @override
  Future<BilibiliSearchPage> searchVideos(
    String keyword, {
    int page = 1,
  }) async {
    keywords.add(keyword);
    return BilibiliSearchPage(
      page: 1,
      totalPages: 1,
      videos: List<BilibiliSearchHit>.generate(
        20,
        (index) => BilibiliSearchHit(
          bvid: 'BV${index.toString().padLeft(10, '0')}',
          title: '测试番剧 · 视频 ${index + 1}',
          author: '测试作者',
          duration: const Duration(minutes: 24),
          score: 100,
        ),
      ),
    );
  }

  @override
  Future<BilibiliVideo> loadVideo(String input) async => BilibiliVideo(
    bvid: input,
    title: '测试番剧合集',
    parts: const <BilibiliPart>[
      BilibiliPart(
        cid: 50,
        page: 1,
        title: '第5集 雨后的天空',
        duration: Duration(minutes: 24),
      ),
    ],
  );
}

class _Feed extends RssFeedService {
  int calls = 0;
  @override
  Future<RssFeedSnapshot> fetch(String url, {bool force = false}) async {
    calls++;
    return RssFeedSnapshot(
      title: '测试来源',
      fetchedAt: DateTime(2026),
      items: List<RssResource>.generate(
        20,
        (index) => RssResource(
          id: '$index',
          title:
              '[字幕组] 测试番剧 - ${(index + 1).toString().padLeft(2, '0')} [1080p]',
          torrent: 'https://feed.example/${index + 1}.torrent',
          publishedAt: DateTime(2026, 1, index + 1),
        ),
      ),
    );
  }
}

class _Mappings extends BilibiliEpisodeMappingRepository {
  final List<OnlineEpisodeQuery> reads = <OnlineEpisodeQuery>[];
  @override
  Future<BilibiliEpisodeMapping?> find(OnlineEpisodeQuery query) async {
    reads.add(query);
    return null;
  }
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('RESOURCE_SCREENSHOTS')) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey<String>('resource-preview')),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('.local/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  Future<SettingsProvider> settingsWithSource() async {
    final settings = SettingsProvider();
    await settings.initialize();
    while (settings.rssSources.isNotEmpty) {
      await settings.removeRssSource(0);
    }
    await settings.addRssSource(
      '测试来源',
      'https://feed.example/search?keyword={keyword}',
      type: 'search',
    );
    return settings;
  }

  for (final dark in <bool>[false, true]) {
    testWidgets(
      'resource tabs preserve independent results, filters and scroll in ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final settings = await settingsWithSource();
        addTearDown(settings.dispose);
        final videos = _Videos();
        final feed = _Feed();
        final mappings = _Mappings();
        if (const bool.fromEnvironment('RESOURCE_SCREENSHOTS')) {
          await tester.runAsync(() async {
            final font = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
            await (FontLoader(
              'ResourcePreview',
            )..addFont(Future.value(ByteData.sublistView(font)))).load();
            final icons = await File(
              '.local/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes();
            await (FontLoader(
              'MaterialIcons',
            )..addFont(Future.value(ByteData.sublistView(icons)))).load();
          });
        }
        await tester.pumpWidget(
          ChangeNotifierProvider<SettingsProvider>.value(
            value: settings,
            child: RepaintBoundary(
              key: const ValueKey<String>('resource-preview'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                  useMaterial3: true,
                  brightness: dark ? Brightness.dark : Brightness.light,
                  fontFamily: const bool.fromEnvironment('RESOURCE_SCREENSHOTS')
                      ? 'ResourcePreview'
                      : 'Roboto',
                ),
                home: ResourceSearchPage(
                  animeName: '测试番剧',
                  aliases: const <String>['测试番剧', 'Test Anime'],
                  bangumiSubjectId: 42,
                  bilibiliService: videos,
                  bilibiliAuth: _Auth(),
                  bilibiliMappings: mappings,
                  feedService: feed,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(videos.keywords, <String>['测试番剧']);
        expect(find.byType(MagnetConfigPage), findsNothing);
        await _capture(tester, 'resource-search-${dark ? 'dark' : 'light'}');

        final biliList = find.byKey(
          const ValueKey<String>('bilibili-search-results'),
        );
        await tester.drag(biliList, const Offset(0, -380));
        await tester.pumpAndSettle();
        final biliOffset = tester.widget<ListView>(biliList).controller!.offset;

        await tester.tap(find.text('网站资源'));
        await tester.pumpAndSettle();
        expect(feed.calls, 0);
        expect(
          tester.widget<TextField>(_field('番剧名称')).controller!.text,
          '测试番剧',
        );
        expect(
          tester.widget<TextField>(_field('指定集数（可选）')).controller!.text,
          isEmpty,
        );
        await _capture(tester, 'resource-websites-${dark ? 'dark' : 'light'}');

        await tester.tap(find.text('筛选与来源'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(_field('必须包含'));
        await tester.enterText(_field('必须包含'), '字幕组');
        await tester.ensureVisible(_field('画质过滤'));
        await tester.enterText(_field('画质过滤'), '1080');
        tester.testTextInput.hide();
        final searchButton = find.widgetWithText(FilledButton, '搜索资源');
        await tester.ensureVisible(searchButton);
        await tester.tap(searchButton);
        await tester.pumpAndSettle();
        expect(feed.calls, 1);

        final websiteList = find.byKey(
          const ValueKey<String>('website-resource-results'),
        );
        await tester.drag(websiteList, const Offset(0, -600));
        await tester.pumpAndSettle();
        final websiteOffset = tester
            .widget<ListView>(websiteList)
            .controller!
            .offset;
        expect(websiteOffset, greaterThan(0));
        await tester.tap(find.text('B站视频'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ListView>(biliList).controller!.offset,
          closeTo(biliOffset, 0.1),
        );
        expect(videos.keywords.length, 1);
        await tester.tap(find.text('网站资源'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ListView>(websiteList).controller!.offset,
          closeTo(websiteOffset, 0.1),
        );
        expect(feed.calls, 1);
        expect(find.textContaining('搜索结果：20 条'), findsOneWidget);
        tester.widget<ListView>(websiteList).controller!.jumpTo(0);
        await tester.pumpAndSettle();
        final filters = find.text('筛选与来源');
        await tester.ensureVisible(filters);
        if (_field('必须包含').evaluate().isEmpty) {
          await tester.tap(filters);
          await tester.pumpAndSettle();
        }
        expect(
          tester.widget<TextField>(_field('必须包含')).controller!.text,
          '字幕组',
        );
        expect(
          tester.widget<TextField>(_field('画质过滤')).controller!.text,
          '1080',
        );
        expect(mappings.reads, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'aliases search immediately and whole-subject browsing has no episode mapping',
    (tester) async {
      final videos = _Videos();
      final mappings = _Mappings();
      await tester.pumpWidget(
        MaterialApp(
          home: ResourceSearchPage(
            animeName: '测试番剧',
            aliases: const <String>['测试番剧', 'Test Anime'],
            bangumiSubjectId: 42,
            bilibiliService: videos,
            bilibiliAuth: _Auth(),
            bilibiliMappings: mappings,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('别名'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Anime'));
      await tester.pumpAndSettle();
      expect(videos.keywords, <String>['测试番剧', 'Test Anime']);
      await tester.tap(find.text('测试番剧 · 视频 1'));
      await tester.pumpAndSettle();
      final details = tester.widget<BilibiliVideoDetailsPage>(
        find.byType(BilibiliVideoDetailsPage),
      );
      expect(details.episodeQuery, isNull);
      expect(details.subjectTitle, '测试番剧');
      expect(details.bangumiSubjectId, 42);
      expect(mappings.reads, isEmpty);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Test Anime',
      );
      expect(videos.keywords.length, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'episode search keeps its identity and suggests a matching part',
    (tester) async {
      final settings = await settingsWithSource();
      addTearDown(settings.dispose);
      final videos = _Videos();
      final mappings = _Mappings();
      const query = OnlineEpisodeQuery(
        bangumiSubjectId: 42,
        bangumiEpisodeId: 105,
        subjectTitle: '测试番剧',
        aliases: <String>['Test Anime'],
        episodeNumber: 5,
        episodeTitle: '雨后的天空',
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settings,
          child: MaterialApp(
            home: ResourceSearchPage(
              animeName: query.subjectTitle,
              aliases: query.aliases,
              bangumiSubjectId: query.bangumiSubjectId,
              episodeQuery: query,
              bilibiliService: videos,
              bilibiliAuth: _Auth(),
              bilibiliMappings: mappings,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('测试番剧 · 视频 1'));
      await tester.pumpAndSettle();
      expect(mappings.reads, <OnlineEpisodeQuery>[query]);
      expect(find.textContaining('集数匹配建议'), findsOneWidget);
      expect(find.text('建议'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('网站资源'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_field('指定集数（可选）')).controller!.text,
        '5',
      );
      expect(find.text('当前：雨后的天空'), findsOneWidget);
      expect(videos.keywords.length, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
