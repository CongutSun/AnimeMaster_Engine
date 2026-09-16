import 'dart:async';

import 'package:animemaster/src/models/dandanplay_models.dart';
import 'package:animemaster/src/screens/dandanplay_discovery_page.dart';
import 'package:animemaster/src/services/dandanplay_service.dart';
import 'package:animemaster/src/widgets/dandanplay_send_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeService extends DandanplayService {
  final calls = <String, Completer<Map<String, dynamic>>>{};
  final sent = Completer<Map<String, dynamic>>();
  int sends = 0;
  bool available = true;
  @override
  Future<Map<String, dynamic>> discovery({
    String category = 'hot',
    String period = 'week',
  }) => (calls[category] = Completer<Map<String, dynamic>>()).future;
  @override
  Future<Map<String, dynamic>> capabilities() async => {
    'send': true,
    'quota': {
      'available': available,
      'dailyRemaining': available ? 10 : 0,
      'monthlyRemaining': 240,
    },
  };
  @override
  Future<Map<String, dynamic>> sendComment(
    DandanplayMatchResult match, {
    required String text,
    required Duration position,
    required String requestId,
  }) {
    sends++;
    return sent.future;
  }

  @override
  Future<Map<String, dynamic>> details(
    String animeId, {
    bool bangumi = false,
  }) async => {
    'bangumi': {
      'animeTitle': '长篇动画',
      'summary': '作品简介',
      'episodes': List.generate(
        1200,
        (i) => {'episodeNumber': '${i + 1}', 'episodeTitle': '剧集 ${i + 1}'},
      ),
    },
  };
}

const match = DandanplayMatchResult(
  episodeId: 1,
  animeId: 1,
  animeTitle: '测试',
  episodeTitle: '第1集',
);

void main() {
  testWidgets(
    'yearly ranking shares discovery navigation without fetching heat',
    (tester) async {
      final service = FakeService();
      await tester.pumpWidget(
        MaterialApp(
          home: DandanplayDiscoveryPage(
            service: service,
            initialCategory: 'rating',
            yearTop: const [],
          ),
        ),
      );
      await tester.pump();
      expect(find.text('发现动漫'), findsOneWidget);
      expect(find.text('年度高分'), findsOneWidget);
      expect(service.calls, isEmpty);
      await tester.tap(find.text('热播榜'));
      await tester.pump();
      expect(service.calls.containsKey('hot'), isTrue);
      service.calls['hot']!.complete({'bangumiList': []});
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'switching discovery tabs discards older responses on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FakeService();
      await tester.pumpWidget(
        MaterialApp(home: DandanplayDiscoveryPage(service: service)),
      );
      await tester.tap(find.text('飙升榜'));
      await tester.pump();
      service.calls['rising']!.complete({
        'bangumiList': [
          {'animeId': 2, 'animeTitle': '正确榜单'},
        ],
      });
      await tester.pumpAndSettle();
      service.calls['hot']!.complete({
        'bangumiList': [
          {'animeId': 1, 'animeTitle': '过期榜单'},
        ],
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('正确榜单'), findsOneWidget);
      expect(find.textContaining('过期榜单'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('long series builds only visible episode tiles', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DandanplayDetailPage(
          animeId: '1',
          title: '长篇动画',
          service: FakeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ListTile).evaluate().length, lessThan(30));
    expect(find.text('剧集 · 1200'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('exhausted quota disables sending', (tester) async {
    final service = FakeService()..available = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DandanplaySendSheet(
            service: service,
            match: match,
            position: Duration.zero,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '你好');
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(service.sends, 0);
  });
  testWidgets('double tap sends once and unknown outcomes prevent retries', (
    tester,
  ) async {
    final service = FakeService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DandanplaySendSheet(
            service: service,
            match: match,
            position: Duration.zero,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '你好');
    await tester.tap(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(service.sends, 1);
    service.sent.completeError(
      const DandanplayException('发送结果待确认', code: 'send_unknown'),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.text('发送结果待确认'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
