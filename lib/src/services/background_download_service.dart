import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BackgroundDownloadService {
  static const MethodChannel _channel = MethodChannel(
    'com.animemaster.app/background_download',
  );

  static bool? _active;
  static Future<void> _pending = Future<void>.value();

  static void initialize(Future<void> Function() pauseAll) {
    _active = null;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'pauseAll') await pauseAll();
    });
  }

  static Future<void> setActive(bool active) {
    _pending = _pending.then((_) => _apply(active));
    return _pending;
  }

  static Future<void> _apply(bool active) async {
    if (_active == active) {
      return;
    }

    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      await _channel.invokeMethod<void>(active ? 'start' : 'stop');
      _active = active;
    } catch (_) {
      _active = null;
    }
  }

  static Future<void> openSettings() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('openSettings');
  }
}
