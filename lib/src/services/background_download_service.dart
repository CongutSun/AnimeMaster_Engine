import 'dart:io';

import 'package:flutter/services.dart';

class BackgroundDownloadService {
  static const MethodChannel _channel = MethodChannel(
    'com.animemaster.app/background_download',
  );

  static bool _active = false;

  static Future<void> setActive(bool active) async {
    if (_active == active) {
      return;
    }
    _active = active;

    if (!Platform.isAndroid) {
      return;
    }

    try {
      await _channel.invokeMethod<void>(active ? 'start' : 'stop');
    } catch (_) {
      _active = !active;
    }
  }
}
