import 'package:animemaster/src/models/dandanplay_models.dart';
import 'package:animemaster/src/widgets/danmaku_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget scene({
  int mode = 1,
  double opacity = 1,
  double fontSize = 20,
  bool paused = false,
  Size size = const Size(800, 450),
  VoidCallback? completed,
  Duration? position,
  double playbackRate = 1,
}) => MaterialApp(
  home: Scaffold(
    backgroundColor: Colors.black,
    body: Center(
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: DanmakuOverlay(
          items: [
            ActiveDanmakuItem(
              id: 1,
              lane: 0,
              comment: DandanplayComment(
                id: 1,
                appearAt: Duration.zero,
                mode: mode,
                color: 0xffffff,
                userId: 'test',
                text: '渲染回归测试',
              ),
            ),
          ],
          fontSize: fontSize,
          opacity: opacity,
          speed: 1,
          showBackground: false,
          showStroke: true,
          paused: paused,
          onCompleted: (_) => completed?.call(),
          position: position,
          playbackRate: playbackRate,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('seek restores screen position and backwards seek rewinds it', (
    tester,
  ) async {
    await tester.pumpWidget(
      scene(paused: true, position: const Duration(seconds: 4)),
    );
    final middle = tester.widget<Positioned>(find.byType(Positioned)).left!;
    expect(middle, greaterThan(0));
    expect(middle, lessThan(600));
    await tester.pumpWidget(
      scene(paused: true, position: const Duration(seconds: 2)),
    );
    expect(
      tester.widget<Positioned>(find.byType(Positioned)).left!,
      greaterThan(middle),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
  testWidgets('playback rate scales remaining bullet animation', (
    tester,
  ) async {
    await tester.pumpWidget(scene(position: Duration.zero, playbackRate: 2));
    await tester.pump(const Duration(seconds: 2));
    final fast = tester.widget<Positioned>(find.byType(Positioned)).left!;
    await tester.pumpWidget(
      scene(paused: true, position: const Duration(seconds: 4)),
    );
    expect(
      tester.widget<Positioned>(find.byType(Positioned)).left!,
      closeTo(fast, 1),
    );
    expect(tester.takeException(), isNull);
  });
  for (final mode in [1, 4, 5]) {
    for (final opacity in [1.0, 0.8, 0.35]) {
      testWidgets(
        'mode $mode opacity $opacity renders through orientation changes',
        (tester) async {
          tester.view.physicalSize = const Size(900, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            scene(mode: mode, opacity: opacity, size: const Size(390, 800)),
          );
          await tester.pump(const Duration(milliseconds: 800));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(scene(mode: mode, opacity: opacity));
          await tester.pump(const Duration(milliseconds: 500));
          expect(tester.takeException(), isNull);
          expect(find.byType(ErrorWidget), findsNothing);
          expect(find.text('渲染回归测试'), findsOneWidget);
          final position = tester.widget<Positioned>(find.byType(Positioned));
          expect(position.left!.isFinite, isTrue);
          expect(position.top!.isFinite, isTrue);
          if (mode != 1 || opacity < 0.99) {
            expect(position.child, isA<Opacity>());
          }
          await tester.pumpWidget(
            scene(mode: mode, opacity: opacity, size: const Size(390, 800)),
          );
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  testWidgets('opacity changes affect existing bullets without layout errors', (
    tester,
  ) async {
    await tester.pumpWidget(scene());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(scene(opacity: 0.35));
    final dimmed = tester.widget<Positioned>(find.byType(Positioned));
    expect((dimmed.child as Opacity).opacity, 0.35);
    await tester.pumpWidget(scene());
    expect(
      tester.widget<Positioned>(find.byType(Positioned)).child,
      isNot(isA<Opacity>()),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('initially paused bullets stay still, resume and complete once', (
    tester,
  ) async {
    var completed = 0;
    await tester.pumpWidget(scene(paused: true, completed: () => completed++));
    final initial = tester.widget<Positioned>(find.byType(Positioned)).left;
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Positioned>(find.byType(Positioned)).left, initial);
    await tester.pumpWidget(scene(completed: () => completed++));
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.widget<Positioned>(find.byType(Positioned)).left,
      lessThan(initial!),
    );
    await tester.pump(const Duration(seconds: 20));
    expect(completed, 1);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
