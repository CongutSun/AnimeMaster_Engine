import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:animemaster/src/api/dio_client.dart';
import 'package:animemaster/src/providers/settings_provider.dart';
import 'package:animemaster/src/screens/collection_page.dart';
import 'package:animemaster/src/screens/magnet_config_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Settings extends SettingsProvider {
  @override
  bool get isLoaded => true;
  @override
  String get bgmAcc => 'test';
  @override
  String get bgmToken => 'token';
  @override
  Future<bool> ensureBangumiAccessToken({bool forceRefresh = false}) async =>
      true;
}

class _ProgressAdapter implements HttpClientAdapter {
  final releaseWrite = Completer<void>();
  int progress = 5;
  int writes = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    if (options.method == 'POST') {
      writes++;
      await releaseWrite.future;
      progress = 6;
    }
    return ResponseBody.fromString(
      jsonEncode({
        'data': [
          {
            'subject': {'id': 1, 'name': '测试番剧', 'eps': 12},
            'ep_status': progress,
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets(
    'progress survives reopening and repeated taps cannot submit concurrent writes',
    (tester) async {
      final dio = DioClient().dio;
      final previous = dio.httpClientAdapter;
      final adapter = _ProgressAdapter();
      dio.httpClientAdapter = adapter;
      addTearDown(() => dio.httpClientAdapter = previous);
      final settings = _Settings();
      Widget page(Key key) => ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(home: CollectionPage(key: key)),
      );
      await tester.pumpWidget(page(const ValueKey(1)));
      await tester.pumpAndSettle();
      expect(find.text('观看进度 5 / 12 集'), findsOneWidget);
      await tester.tap(find.text('看完+1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('看完+1'));
      await tester.pumpAndSettle();
      expect(adapter.writes, 1);
      adapter.releaseWrite.complete();
      await tester.pumpAndSettle();
      expect(find.text('观看进度 6 / 12 集'), findsOneWidget);
      await tester.pumpWidget(page(const ValueKey(2)));
      await tester.pumpAndSettle();
      expect(find.text('观看进度 6 / 12 集'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('search fits a phone and advanced fields start collapsed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: _Settings(),
        child: const MaterialApp(
          home: MagnetConfigPage(
            animeName: '测试番剧',
            aliases: ['Test'],
            initialEpisodeNumber: 6,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('搜索资源'), findsOneWidget);
    expect(find.text('必须包含'), findsNothing);
    await tester.tap(find.text('筛选与来源'));
    await tester.pumpAndSettle();
    expect(find.text('必须包含'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
