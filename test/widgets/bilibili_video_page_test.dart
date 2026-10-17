import 'dart:async';

import 'package:animemaster/src/models/bilibili_video.dart';
import 'package:animemaster/src/models/playable_media.dart';
import 'package:animemaster/src/screens/bilibili_video_details_page.dart';
import 'package:animemaster/src/screens/bilibili_video_page.dart';
import 'package:animemaster/src/services/bilibili_auth_service.dart';
import 'package:animemaster/src/services/bilibili_video_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class _Auth extends BilibiliAuthService {
  @override
  Future<void> initialize() async {}
}

class _Service extends BilibiliVideoService {
  int? requestedCid;
  final List<(String, int)> searches = <(String, int)>[];
  Completer<void>? videoGate;
  bool failVideo = false;

  @override
  Future<BilibiliSearchPage> searchVideos(
    String keyword, {
    int page = 1,
  }) async {
    searches.add((keyword, page));
    return BilibiliSearchPage(
      page: page,
      totalPages: 2,
      videos: List<BilibiliSearchHit>.generate(
        20,
        (i) => BilibiliSearchHit(
          bvid: 'BV${(page * 100 + i).toString().padLeft(10, '0')}',
          title: '搜索结果 $page-${i + 1}',
          author: '测试作者',
          duration: const Duration(minutes: 2),
          score: 100,
        ),
      ),
    );
  }

  @override
  Future<BilibiliVideo> loadVideo(String input) async {
    final String bvid = BilibiliVideoService.parseBvid(input);
    if (videoGate != null) await videoGate!.future;
    if (failVideo) throw const BilibiliVideoException('视频暂时无法读取。');
    return BilibiliVideo(
      bvid: bvid,
      title: '测试视频',
      parts: const <BilibiliPart>[
        BilibiliPart(
          cid: 101,
          page: 1,
          title: '开场',
          duration: Duration(seconds: 60),
        ),
        BilibiliPart(
          cid: 202,
          page: 2,
          title: '正片',
          duration: Duration(seconds: 600),
        ),
      ],
    );
  }

  @override
  Future<PlayableMedia> resolvePart(
    BilibiliVideo video,
    BilibiliPart part, {
    int? preferredQuality,
  }) async {
    requestedCid = part.cid;
    throw const BilibiliVideoException('当前视频需要额外权限。');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues(<String, String>{});

  testWidgets('invalid input is recoverable and tapping P2 resolves its cid', (
    tester,
  ) async {
    final service = _Service();
    await tester.pumpWidget(
      MaterialApp(
        home: BilibiliVideoPage(service: service, auth: _Auth()),
      ),
    );
    await tester.enterText(find.byType(TextField), 'BV123');
    await tester.tap(find.text('打开或搜索'));
    await tester.pumpAndSettle();
    expect(find.text('请输入完整的 BV 号或 B站视频 HTTPS 链接。'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'BV1xx411c7mD');
    await tester.tap(find.text('打开或搜索'));
    await tester.pumpAndSettle();
    expect(find.text('P1 · 开场'), findsOneWidget);
    expect(find.text('P2 · 正片'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
    await tester.tap(find.text('P2 · 正片'));
    await tester.pumpAndSettle();
    expect(service.requestedCid, 202);
    expect(find.text('当前视频需要额外权限。'), findsOneWidget);
    await tester.tap(find.text('P1 · 开场'));
    await tester.pumpAndSettle();
    expect(service.requestedCid, 101);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'BV1xx411c7mD',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('toolbar and system back preserve query, pagination and scroll', (
    tester,
  ) async {
    final service = _Service();
    await tester.pumpWidget(
      MaterialApp(
        home: BilibiliVideoPage(
          service: service,
          auth: _Auth(),
          initialKeyword: '测试番剧',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final list = find.byKey(const ValueKey<String>('bilibili-search-results'));
    final scrollable = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('加载更多'),
      350,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('搜索结果 2-8'),
      250,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    final double offset = tester.widget<ListView>(list).controller!.offset;
    expect(offset, greaterThan(0));
    await tester.tap(find.text('搜索结果 2-8'));
    await tester.pumpAndSettle();
    expect(find.byType(BilibiliVideoDetailsPage), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ListView>(list).controller!.offset,
      closeTo(offset, 0.1),
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '测试番剧',
    );
    expect(service.searches, <(String, int)>[('测试番剧', 1), ('测试番剧', 2)]);
    expect(find.text('搜索结果 2-8').hitTestable(), findsOneWidget);

    await tester.tap(find.text('搜索结果 2-8'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BilibiliVideoDetailsPage), findsNothing);
    expect(
      tester.widget<ListView>(list).controller!.offset,
      closeTo(offset, 0.1),
    );
    expect(service.searches.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving a loading detail cannot reopen it after the request', (
    tester,
  ) async {
    final service = _Service()..videoGate = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: BilibiliVideoPage(
          service: service,
          auth: _Auth(),
          initialKeyword: '测试番剧',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索结果 1-1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    service.videoGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(BilibiliVideoDetailsPage), findsNothing);
    expect(find.text('搜索结果 1-1'), findsOneWidget);
    expect(service.searches.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail failures can retry without losing the parent search', (
    tester,
  ) async {
    final service = _Service()..failVideo = true;
    await tester.pumpWidget(
      MaterialApp(
        home: BilibiliVideoPage(
          service: service,
          auth: _Auth(),
          initialKeyword: '测试番剧',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索结果 1-1'));
    await tester.pumpAndSettle();
    expect(find.text('视频暂时无法读取。'), findsOneWidget);
    service.failVideo = false;
    await tester.tap(find.text('重新读取'));
    await tester.pumpAndSettle();
    expect(find.text('P2 · 正片'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('搜索结果 1-1'), findsOneWidget);
    expect(service.searches.length, 1);
    expect(tester.takeException(), isNull);
  });
}
