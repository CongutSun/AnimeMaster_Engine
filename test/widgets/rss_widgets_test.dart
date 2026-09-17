import 'dart:io';
import 'dart:ui' as ui;
import 'package:animemaster/src/models/rss_resource.dart';
import 'package:animemaster/src/providers/settings_provider.dart';
import 'package:animemaster/src/screens/rss_inbox_page.dart';
import 'package:animemaster/src/services/rss_feed_service.dart';
import 'package:animemaster/src/services/rss_inbox_store.dart';
import 'package:animemaster/src/widgets/rss_sources_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Feed extends RssFeedService {
  @override
  Future<RssFeedSnapshot> fetch(String url, {bool force = false}) async =>
      RssFeedSnapshot(
        title: '测试订阅',
        items: const [
          RssResource(
            id: 'one',
            title: '[字幕组] 测试番剧 - 06 [1080p HEVC]',
            torrent: 'https://feed.example/one.torrent',
          ),
        ],
        fetchedAt: DateTime.now(),
      );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
  });
  for (final dark in [false, true]) {
    testWidgets(
      'RSS dialog and inbox fit narrow ${dark ? 'dark' : 'light'} layout',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final settings = SettingsProvider();
        await settings.initialize();
        await settings.addRssSource(
          '我的订阅',
          'https://feed.example/rss?token=test-only',
        );
        if (const bool.fromEnvironment('RSS_SCREENSHOTS')) {
          await tester.runAsync(() async {
            final font = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
            await (FontLoader(
              'RssPreview',
            )..addFont(Future.value(ByteData.sublistView(font)))).load();
          });
        }
        final theme = ThemeData(
          fontFamily: const bool.fromEnvironment('RSS_SCREENSHOTS')
              ? 'RssPreview'
              : 'Roboto',
          useMaterial3: true,
          brightness: dark ? Brightness.dark : Brightness.light,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: RssSourceDialog(
                source: settings.rssSources.last,
                service: _Feed(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final address = tester
            .widgetList<TextField>(find.byType(TextField))
            .last;
        expect(address.obscureText, isTrue);
        await tester.tap(find.text('测试连接'));
        await tester.pumpAndSettle();
        expect(find.textContaining('连接成功'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final store = RssInboxStore(service: _Feed());
        final boundary = GlobalKey();
        await tester.pumpWidget(
          ChangeNotifierProvider<SettingsProvider>.value(
            value: settings,
            child: MaterialApp(
              theme: theme,
              home: RepaintBoundary(
                key: boundary,
                child: RssInboxPage(store: store),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('测试番剧 - 06'), findsOneWidget);
        await tester.tap(find.text('忽略'));
        await tester.pumpAndSettle();
        expect(store.entries.single.state, 'ignored');
        await tester.tap(find.text('已处理'));
        await tester.pumpAndSettle();
        expect(find.textContaining('已忽略'), findsOneWidget);
        expect(find.textContaining('token='), findsNothing);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('RSS_SCREENSHOTS')) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory('.local/rss-ui').create(recursive: true);
            await File(
              '.local/rss-ui/${dark ? 'dark' : 'light'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      },
    );
  }
}
