import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:animemaster/src/api/dio_client.dart';
import 'package:animemaster/src/providers/settings_provider.dart';
import 'package:animemaster/src/screens/detail_page.dart';
import 'package:animemaster/src/screens/episode_watch_page.dart';
import 'package:animemaster/src/storage/app_database.dart';
import 'package:animemaster/src/widgets/subject_playback_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';

class _Settings extends SettingsProvider {
  @override
  Future<bool> ensureBangumiAccessToken({bool forceRefresh = false}) async =>
      false;
}

class _Catalog implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions request,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final path = request.uri.path;
    final Object data = path.endsWith('/episodes')
        ? {
            'total': 45,
            'data': List.generate(
              45,
              (i) => {'ep': i + 1, 'name': '标题 ${i + 1}'},
            ),
          }
        : path.endsWith('/345679')
        ? {'name': '测试番', 'eps': 45}
        : [];
    return ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Routes extends NavigatorObserver {
  late Route<dynamic> latest;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      latest = route;
}

PlaybackProgressRecord record(int id, int positionMs) => PlaybackProgressRecord(
  mediaKey: 'episode-$id',
  bangumiSubjectId: 1,
  bangumiEpisodeId: id,
  title: '',
  subjectTitle: '动画',
  episodeLabel: '第40集',
  localFilePath: '/saved.mp4',
  url: '',
  positionMs: positionMs,
  durationMs: 1200000,
  updatedAtMs: id,
);

void main() {
  testWidgets('详情页从首个分页续播第 40 集时播放器仍收到全 45 集', (tester) async {
    final dio = DioClient().dio;
    final previous = dio.httpClientAdapter;
    dio.httpClientAdapter = _Catalog();
    addTearDown(() => dio.httpClientAdapter = previous);
    final observer = _Routes();
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => _Settings(),
        child: MaterialApp(
          navigatorObservers: [observer],
          home: const DetailPage(animeId: 345679, initialName: '测试番'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final actions = tester.widget<SubjectPlaybackActions>(
      find.byType(SubjectPlaybackActions),
    );
    expect(actions.episodes.length, 45);
    final saved = record(40, 754321);
    actions.onResume(actions.episodes[39], saved);
    final route = observer.latest as MaterialPageRoute;
    final player =
        route.builder(tester.element(find.byType(DetailPage)))
            as EpisodeWatchPage;
    expect(
      player.episodes.map((ep) => ep['ep']),
      orderedEquals(List.generate(45, (i) => i + 1)),
    );
    expect(player.initialEpisode['ep'], 40);
    expect(player.initialHistory, same(saved));
    observer.navigator!.removeRoute(route);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('详情主操作随历史与可用缓存更新，保留手动搜索并传递精确续播位置', (tester) async {
    final history = StreamController<PlaybackProgressRecord?>();
    final cached = StreamController<bool>.broadcast();
    final episodes = List.generate(
      45,
      (i) => <String, dynamic>{'id': i + 1, 'ep': i + 1},
    );
    final opens = <(int, Duration, String)>[];
    var searches = 0;
    final watched = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: SubjectPlaybackActions(
            history: history.stream,
            episodes: episodes,
            watchOffline: (id, path) {
              watched.add(id);
              return cached.stream;
            },
            onResume: (ep, record) => opens.add((
              ep['id'] as int,
              Duration(milliseconds: record.positionMs),
              record.localFilePath,
            )),
            onSearch: () => searches++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('搜索资源'));
    expect(searches, 1);
    history.add(record(40, 754321));
    await tester.pump();
    cached.add(true);
    await tester.pump();
    expect(find.text('上次看到 12:34 · 已缓存'), findsOneWidget);
    await tester.tap(find.text('继续看第 40 集'));
    expect(opens.single, (
      40,
      const Duration(milliseconds: 754321),
      '/saved.mp4',
    ));
    await tester.tap(find.byTooltip('搜索资源'));
    expect(searches, 2);
    cached.add(false);
    await tester.pump();
    expect(find.text('上次看到 12:34'), findsOneWidget);
    history.add(record(40, 1189000));
    await tester.pump();
    expect(find.text('搜索资源'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    history.add(record(41, 5000));
    await tester.pump();
    expect(find.text('搜索资源'), findsOneWidget);
    expect(watched, [40]);
    await history.close();
    await cached.close();
  });

  testWidgets('离线剧集目录缺失时仍可按记录续播，小屏大字可操作', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            bottomNavigationBar: SubjectPlaybackActions(
              episodes: const [],
              history: Stream.value(record(9940, 754321)),
              watchOffline: (_, _) => Stream.value(true),
              onResume: (ep, _) => selected = ep,
              onSearch: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('上次看到 12:34 · 已缓存'), findsOneWidget);
    await tester.tap(find.text('继续看第 40 集'));
    expect(selected?['id'], 9940);
    expect(selected?['ep'], 40);
    expect(tester.takeException(), isNull);
  });
}
