import 'dart:async';

import 'package:animemaster/src/services/background_download_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel(
    'com.animemaster.app/background_download',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    BackgroundDownloadService.initialize(() async {});
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'cold restore without tasks sends stop to a restarted service',
    () async {
      final List<String> calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        calls.add(call.method);
        return null;
      });
      await BackgroundDownloadService.setActivity(TransferActivity.idle);
      expect(calls, ['stop']);
    },
  );

  test(
    'rapid start and pause serialize and deduplicate native commands',
    () async {
      final List<String> calls = <String>[];
      final Completer<void> started = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        calls.add(call.method);
        if (call.method == 'start') await started.future;
        return null;
      });
      final Future<void> start = BackgroundDownloadService.setActivity(
        TransferActivity.downloading,
      );
      final Future<void> duplicate = BackgroundDownloadService.setActivity(
        TransferActivity.downloading,
      );
      final Future<void> stop = BackgroundDownloadService.setActivity(
        TransferActivity.idle,
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['start']);
      started.complete();
      await Future.wait([start, duplicate, stop]);
      expect(calls, ['start', 'stop']);
    },
  );

  test(
    'download to sharing updates the same service, duplicate sharing is silent, idle stops it',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      await Future.wait([
        BackgroundDownloadService.setActivity(TransferActivity.downloading),
        BackgroundDownloadService.setActivity(TransferActivity.seeding),
        BackgroundDownloadService.setActivity(TransferActivity.seeding),
        BackgroundDownloadService.setActivity(TransferActivity.idle),
      ]);
      expect(calls.map((call) => call.method), ['start', 'start', 'stop']);
      expect(calls.first.arguments, containsPair('seeding', false));
      expect(calls.first.arguments, containsPair('title', 'AnimeMaster 正在下载'));
      expect(calls[1].arguments, containsPair('seeding', true));
      expect(calls[1].arguments, containsPair('title', 'AnimeMaster 正在分享'));
      expect(calls[1].arguments['text'], contains('上传'));
    },
  );

  test('a rejected foreground start can be retried', () async {
    int calls = 0;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      if (++calls == 1) throw PlatformException(code: 'not_allowed');
      return null;
    });
    await BackgroundDownloadService.setActivity(TransferActivity.downloading);
    await BackgroundDownloadService.setActivity(TransferActivity.downloading);
    expect(calls, 2);
  });
}
