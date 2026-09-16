import 'package:flutter/gestures.dart';

/// Resolves taps immediately without entering Flutter's double-tap arena.
class PlayerTapHandler {
  Duration? _lastTap;
  Offset? _lastPosition;
  final Stopwatch _clock = Stopwatch()..start();

  void handle(
    TapUpDetails details,
    void Function() tap,
    void Function() doubleTap,
  ) {
    final now = _clock.elapsed;
    final isDouble =
        _lastTap != null &&
        now - _lastTap! <= const Duration(milliseconds: 280) &&
        (details.globalPosition - _lastPosition!).distance <= 32;
    if (isDouble) {
      reset();
      doubleTap();
    } else {
      _lastTap = now;
      _lastPosition = details.globalPosition;
      tap();
    }
  }

  void reset() {
    _lastTap = null;
    _lastPosition = null;
  }
}
