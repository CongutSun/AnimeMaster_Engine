import 'dart:async';
import 'package:animemaster/src/widgets/app_feedback.dart';
import 'package:animemaster/src/utils/magnet_action_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('连续缓存合并、有操作按钮也限时关闭，跨页清除弹幕提示', (tester) async {
    late BuildContext owner;
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [AppFeedback.observer],
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              owner = ctx;
              return const Text('首页');
            },
          ),
        ),
      ),
    );
    final notice = SnackBar(
      content: const Text('已加入缓存队列'),
      action: SnackBarAction(label: '下载中心', onPressed: () {}),
    );
    for (var i = 0; i < 3; i++) {
      AppFeedback.show(owner, notice, download: true);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('已加入 3 个缓存任务'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    AppFeedback.show(
      owner,
      SnackBar(
        content: const Text('弹幕匹配失败'),
        action: SnackBarAction(label: '手动匹配', onPressed: () {}),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(
      Navigator.of(owner).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('下一页')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    Navigator.of(owner).pop();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
  testWidgets('同一剧集自动匹配多次失败仅提示一次，换集后可再次匹配', (tester) async {
    late BuildContext owner;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              owner = ctx;
              return const Text('播放器');
            },
          ),
        ),
      ),
    );
    final prompt = DanmakuMatchPrompt();
    prompt.show(owner, 'ep1', () {});
    await tester.pumpAndSettle();
    expect(find.text('手动匹配'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    prompt.show(owner, 'ep1', () {});
    await tester.pumpAndSettle();
    expect(find.text('手动匹配'), findsNothing);
    prompt.show(owner, 'ep2', () {});
    await tester.pumpAndSettle();
    expect(find.text('手动匹配'), findsOneWidget);
  });

  testWidgets('缓冲探测不并发，切到后台后到达的就绪结果不会关闭下一页', (tester) async {
    final pending = Completer<(double, bool)>();
    var checks = 0;
    late BuildContext owner;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              owner = ctx;
              return const Text('首页');
            },
          ),
        ),
      ),
    );
    final wait = showDialog<bool>(
      context: owner,
      builder: (_) => PlaybackBufferDialog(
        check: () {
          checks++;
          return pending.future;
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(checks, 1);
    await tester.tap(find.text('转入后台下载'));
    await tester.pump();
    expect(await wait, false);
    unawaited(
      Navigator.of(owner).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('下一页')),
        ),
      ),
    );
    pending.complete((1.0, true));
    await tester.pumpAndSettle();
    expect(find.text('下一页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
