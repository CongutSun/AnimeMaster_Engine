import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum TransferActivity { idle, downloading, seeding }

class BackgroundDownloadService {
  static const MethodChannel _channel = MethodChannel(
    'com.animemaster.app/background_download',
  );

  static TransferActivity? _activity;
  static Future<void> _pending = Future<void>.value();

  static void initialize(Future<void> Function() pauseAll) {
    _activity = null;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'pauseAll') await pauseAll();
    });
  }

  static Future<void> setActivity(TransferActivity activity) {
    _pending = _pending.then((_) => _apply(activity));
    return _pending;
  }

  static Future<void> _apply(TransferActivity activity) async {
    if (_activity == activity) {
      return;
    }

    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      if (activity == TransferActivity.idle) {
        await _channel.invokeMethod<void>('stop');
      } else {
        final seeding = activity == TransferActivity.seeding;
        await _channel.invokeMethod<void>('start', {
          'seeding': seeding,
          'title': seeding ? 'AnimeMaster 正在分享' : 'AnimeMaster 正在下载',
          'text': seeding ? '正在上传已完成的资源，可在下载中心停止做种。' : '可在下载中心查看进度或暂停任务。',
        });
      }
      _activity = activity;
    } catch (_) {
      _activity = null;
    }
  }

  static Future<void> openSettings() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('openSettings');
  }
}
