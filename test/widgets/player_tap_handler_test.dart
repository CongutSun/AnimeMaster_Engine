import 'package:animemaster/src/utils/player_tap_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('single tap is immediate and second nearby tap plays once', (
    tester,
  ) async {
    final handler = PlayerTapHandler();
    var taps = 0;
    var doubles = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) =>
              handler.handle(details, () => taps++, () => doubles++),
          onTapCancel: handler.reset,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.tapAt(const Offset(100, 100));
    expect(taps, 1);
    expect(doubles, 0);
    await tester.tapAt(const Offset(100, 100));
    expect(taps, 1);
    expect(doubles, 1);
    await tester.tapAt(const Offset(100, 100));
    await tester.tapAt(const Offset(300, 300));
    expect(taps, 3);
    expect(doubles, 1);
  });
}
