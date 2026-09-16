import 'package:animemaster/src/widgets/playback_seek_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('drag previews locally and commits only on release', (
    tester,
  ) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackSeekSlider(
            position: Duration.zero,
            duration: const Duration(seconds: 100),
            onSeek: seeks.add,
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    expect(seeks, isEmpty);
    await gesture.up();
    await tester.pump();
    expect(seeks, hasLength(1));
    expect(seeks.single, greaterThan(Duration.zero));
  });
}
